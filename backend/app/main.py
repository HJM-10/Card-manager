import hashlib
import os
import secrets
from datetime import datetime, timezone
from typing import Annotated, Literal
from uuid import UUID, uuid4

from fastapi import Depends, FastAPI, HTTPException, Query, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from psycopg.errors import UniqueViolation
from pydantic import AwareDatetime, BaseModel, ConfigDict, EmailStr, Field, field_validator
from pwdlib import PasswordHash

from .db import connect
from .purchases import PurchaseInput, SimulationInput, RefundInput, TransactionRecord, TRANSACTION_SELECT, require_category, save_purchase, save_refund
from .csv_imports import CsvPreviewInput, CsvConfirmation, preview_import, confirm_import, public_batch
from .budgets import BudgetInput, reporting_month, save_budget, monthly_report
from .notifications import DeviceInput, ObservationInput, register_device, cancel_devices, EVENT_SELECT

app = FastAPI(title='SpendTrail API', version='0.1.0')
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv('CORS_ORIGINS', 'http://localhost:5173').split(','),
    allow_methods=['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
    allow_headers=['Authorization', 'Content-Type'],
)
password_hash = PasswordHash.recommended()
dummy_hash = password_hash.hash('dummy-password-never-used-for-login')
bearer = HTTPBearer(auto_error=False)


class Input(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)


class Login(Input):
    email: EmailStr
    password: str = Field(min_length=10, max_length=128)

    # Password whitespace is significant.
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=False)


class Register(Login):
    name: str = Field(min_length=1, max_length=50)

    @field_validator('name')
    @classmethod
    def name_not_blank(cls, value):
        if not value.strip():
            raise ValueError('Name is required')
        return value.strip()


class BiometricCredential(Input):
    refresh_token: str = Field(min_length=32, max_length=128)


class CardInput(Input):
    label: str = Field(min_length=1, max_length=50)
    network: Literal['visa', 'mastercard']
    last4: str = Field(pattern=r'^[0-9]{4}$')
    expiry_month: int = Field(ge=1, le=12)
    expiry_year: int = Field(ge=2026, le=2100)


class CategoryInput(Input):
    name: str = Field(min_length=1, max_length=50)


class CategoryAssignment(Input):
    category_id: UUID | None


DEFAULT_CATEGORIES = ('Groceries', 'Food', 'Transport', 'Shopping', 'Bills', 'Other')


def digest(token):
    return hashlib.sha256(token.encode()).hexdigest()


def current_session(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)):
    if credentials is None:
        raise HTTPException(401, 'Please sign in', headers={'WWW-Authenticate': 'Bearer'})
    with connect() as db:
        user = db.execute(
            '''SELECT u.id, u.email, u.name, s.token_hash, s.biometric_session_id FROM sessions s
               JOIN users u ON u.id = s.user_id
               WHERE s.token_hash = %s AND s.expires_at > now()
                 AND (s.biometric_session_id IS NULL OR EXISTS (
                     SELECT 1 FROM biometric_sessions b WHERE b.id = s.biometric_session_id
                       AND NOT b.revoked AND b.expires_at > now()))''',
            (digest(credentials.credentials),),
        ).fetchone()
    if not user:
        raise HTTPException(401, 'Session expired. Please sign in again', headers={'WWW-Authenticate': 'Bearer'})
    return user


def public_user(user):
    return {key: user[key] for key in ('id', 'email', 'name')}


def issue_session(db, user, biometric_id=None):
    token = secrets.token_urlsafe(32)
    db.execute(
        """INSERT INTO sessions (token_hash, user_id, expires_at, biometric_session_id)
           VALUES (%s, %s, LEAST(now() + interval '12 hours',
               (SELECT expires_at FROM biometric_sessions WHERE id = %s)), %s)""",
        (digest(token), user['id'], biometric_id, biometric_id),
    )
    return {'access_token': token, 'token_type': 'bearer', 'user': public_user(user)}


@app.get('/health')
def health():
    with connect() as db:
        db.execute('SELECT 1')
    return {'status': 'ok'}


@app.post('/auth/register', status_code=201)
def register(body: Register, response: Response):
    response.headers['Cache-Control'] = 'no-store'
    try:
        with connect() as db:
            user = db.execute(
                'INSERT INTO users (id, email, name, password_hash) VALUES (%s, %s, %s, %s) RETURNING id, email, name',
                (uuid4(), str(body.email).lower(), body.name, password_hash.hash(body.password)),
            ).fetchone()
            db.cursor().executemany(
                'INSERT INTO categories (id, user_id, name) VALUES (%s, %s, %s)',
                [(uuid4(), user['id'], name) for name in DEFAULT_CATEGORIES],
            )
            return issue_session(db, user)
    except UniqueViolation:
        raise HTTPException(409, 'An account with this email already exists') from None


@app.post('/auth/login')
def login(body: Login, response: Response):
    response.headers['Cache-Control'] = 'no-store'
    with connect() as db:
        user = db.execute('SELECT * FROM users WHERE email = %s', (str(body.email).lower(),)).fetchone()
        valid = password_hash.verify(body.password, user['password_hash'] if user else dummy_hash)
        if not user or not valid:
            raise HTTPException(401, 'Incorrect email or password')
        return issue_session(db, user)


@app.get('/auth/me')
def me(user=Depends(current_session)):
    return public_user(user)


@app.delete('/auth/session', status_code=204)
def logout(user=Depends(current_session)):
    with connect() as db:
        current = db.execute('SELECT biometric_session_id FROM sessions WHERE token_hash = %s FOR UPDATE', (user['token_hash'],)).fetchone()
        if current is None:
            return
        if current['biometric_session_id'] is not None:
            db.execute('UPDATE biometric_sessions SET revoked = true WHERE user_id = %s AND id = %s', (user['id'], current['biometric_session_id']))
            hashes = [row['token_hash'] for row in db.execute('SELECT token_hash FROM sessions WHERE biometric_session_id = %s', (current['biometric_session_id'],)).fetchall()]
            cancel_devices(db, user['id'], session_hashes=hashes)
        else:
            cancel_devices(db, user['id'], session_hashes=[user['token_hash']])
            db.execute('DELETE FROM sessions WHERE token_hash = %s', (user['token_hash'],))


@app.delete('/auth/access', status_code=204)
def lock_access(user=Depends(current_session)):
    # Lock this app instance without revoking its biometric credential.
    with connect() as db:
        db.execute('SELECT token_hash FROM sessions WHERE token_hash = %s FOR UPDATE', (user['token_hash'],))
        cancel_devices(db, user['id'], session_hashes=[user['token_hash']])
        db.execute('DELETE FROM sessions WHERE token_hash = %s', (user['token_hash'],))


def detach_biometric(db, user):
    current = db.execute('SELECT biometric_session_id FROM sessions WHERE token_hash = %s AND expires_at > now() FOR UPDATE', (user['token_hash'],)).fetchone()
    if current is None:
        raise HTTPException(401, 'Please sign in again')
    if current['biometric_session_id'] is not None:
        active = db.execute('SELECT id FROM biometric_sessions WHERE id = %s AND NOT revoked AND expires_at > now() FOR UPDATE', (current['biometric_session_id'],)).fetchone()
        if active is None:
            raise HTTPException(401, 'Please sign in again')
        revoked_hashes = [row['token_hash'] for row in db.execute('SELECT token_hash FROM sessions WHERE biometric_session_id = %s AND token_hash <> %s', (current['biometric_session_id'], user['token_hash'])).fetchall()]
        cancel_devices(db, user['id'], session_hashes=revoked_hashes)
    db.execute('UPDATE sessions SET biometric_session_id = NULL WHERE token_hash = %s', (user['token_hash'],))
    if current['biometric_session_id'] is not None:
        db.execute('UPDATE biometric_sessions SET revoked = true WHERE user_id = %s AND id = %s', (user['id'], current['biometric_session_id']))


@app.post('/auth/biometric', status_code=201)
def enable_biometric(response: Response, user=Depends(current_session)):
    response.headers['Cache-Control'] = 'no-store'
    token, biometric_id = secrets.token_urlsafe(48), uuid4()
    with connect() as db:
        detach_biometric(db, user)
        saved = db.execute("INSERT INTO biometric_sessions (id, user_id, token_hash, expires_at) VALUES (%s, %s, %s, now() + interval '30 days') RETURNING expires_at", (biometric_id, user['id'], digest(token))).fetchone()
        db.execute('UPDATE sessions SET biometric_session_id = %s WHERE token_hash = %s', (biometric_id, user['token_hash']))
    return {'refresh_token': token, 'expires_at': saved['expires_at']}


@app.delete('/auth/biometric', status_code=204)
def disable_biometric(user=Depends(current_session)):
    with connect() as db:
        detach_biometric(db, user)


@app.post('/auth/biometric/refresh')
def biometric_login(body: BiometricCredential, response: Response):
    response.headers['Cache-Control'] = 'no-store'
    with connect() as db:
        user = db.execute('''SELECT u.id, u.email, u.name, b.id AS biometric_id
            FROM biometric_sessions b JOIN users u ON u.id = b.user_id
            WHERE b.token_hash = %s AND NOT b.revoked AND b.expires_at > now() FOR UPDATE OF b''', (digest(body.refresh_token),)).fetchone()
        if user is None:
            raise HTTPException(401, 'Fingerprint login has expired. Please sign in with your password.')
        return issue_session(db, user, user['biometric_id'])


CARD_COLUMNS = 'id, label, network, last4, expiry_month, expiry_year, archived'


@app.get('/cards')
def cards(include_archived: bool = False, user=Depends(current_session)):
    with connect() as db:
        return db.execute(f'SELECT {CARD_COLUMNS} FROM card_profiles WHERE user_id = %s AND (%s OR NOT archived) ORDER BY created_at, id', (user['id'], include_archived)).fetchall()


def save_card(body, user, card_id=None):
    now = datetime.now(timezone.utc)
    if (body.expiry_year, body.expiry_month) < (now.year, now.month):
        raise HTTPException(422, 'Choose a current or future expiry date')
    values = (body.label, body.network, body.last4, body.expiry_month, body.expiry_year)
    try:
        with connect() as db:
            if card_id is None:
                return db.execute(
                    f'INSERT INTO card_profiles (label, network, last4, expiry_month, expiry_year, user_id, id) VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING {CARD_COLUMNS}',
                    (*values, user['id'], uuid4()),
                ).fetchone()
            row = db.execute(
                f'UPDATE card_profiles SET label=%s, network=%s, last4=%s, expiry_month=%s, expiry_year=%s WHERE id=%s AND user_id=%s AND NOT archived RETURNING {CARD_COLUMNS}',
                (*values, card_id, user['id']),
            ).fetchone()
            if not row:
                raise HTTPException(404, 'Card not found')
            return row
    except UniqueViolation:
        raise HTTPException(409, 'A card with this network and last four digits already exists') from None


@app.post('/cards', status_code=201)
def create_card(body: CardInput, user=Depends(current_session)):
    return save_card(body, user)


@app.patch('/cards/{card_id}')
def update_card(card_id: UUID, body: CardInput, user=Depends(current_session)):
    return save_card(body, user, card_id)


@app.delete('/cards/{card_id}', status_code=204)
def archive_card(card_id: UUID, user=Depends(current_session)):
    with connect() as db:
        row = db.execute('UPDATE card_profiles SET archived=true WHERE id=%s AND user_id=%s AND NOT archived RETURNING id', (card_id, user['id'])).fetchone()
        if not row:
            raise HTTPException(404, 'Card not found')


@app.get('/categories')
def categories(user=Depends(current_session)):
    with connect() as db:
        return db.execute('SELECT id, name FROM categories WHERE user_id = %s ORDER BY lower(name), id', (user['id'],)).fetchall()


@app.post('/categories', status_code=201)
def create_category(body: CategoryInput, user=Depends(current_session)):
    try:
        with connect() as db:
            return db.execute('INSERT INTO categories (id, user_id, name) VALUES (%s, %s, %s) RETURNING id, name', (uuid4(), user['id'], body.name)).fetchone()
    except UniqueViolation:
        raise HTTPException(409, 'A category with this name already exists') from None


@app.put('/devices/{device_id}')
def put_device(device_id: UUID, body: DeviceInput, user=Depends(current_session)):
    with connect() as db:
        return register_device(db, user, device_id, body)


@app.get('/devices/{device_id}')
def get_device(device_id: UUID, user=Depends(current_session)):
    with connect() as db:
        device = db.execute('SELECT id, enabled, platform FROM device_registrations WHERE id = %s AND user_id = %s', (device_id, user['id'])).fetchone()
    if device is None:
        raise HTTPException(404, 'Device not found')
    return device


@app.delete('/devices/{device_id}', status_code=204)
def remove_device(device_id: UUID, user=Depends(current_session)):
    with connect() as db:
        if not db.execute('SELECT id FROM device_registrations WHERE id = %s AND user_id = %s', (device_id, user['id'])).fetchone():
            raise HTTPException(404, 'Device not found')
        cancel_devices(db, user['id'], device_id=device_id)


@app.get('/notifications')
def list_notifications(limit: Annotated[int, Query(ge=1, le=100)] = 25,
                       offset: Annotated[int, Query(ge=0, le=2_147_483_647)] = 0,
                       user=Depends(current_session)):
    with connect() as db:
        return db.execute(EVENT_SELECT + ' WHERE user_id = %s ORDER BY created_at DESC, id DESC LIMIT %s OFFSET %s', (user['id'], limit, offset)).fetchall()


@app.get('/notifications/{event_id}')
def get_notification(event_id: UUID, user=Depends(current_session)):
    with connect() as db:
        event = db.execute(EVENT_SELECT + ' WHERE user_id = %s AND id = %s', (user['id'], event_id)).fetchone()
    if event is None:
        raise HTTPException(404, 'Notification not found')
    return event


@app.post('/notifications/{event_id}/observations', status_code=204)
def observe_notification(event_id: UUID, body: ObservationInput, user=Depends(current_session)):
    column = 'opened_at' if body.action == 'opened' else 'received_at'
    with connect() as db:
        row = db.execute(f'UPDATE notification_events SET {column} = COALESCE({column}, now()), received_at = COALESCE(received_at, now()) WHERE user_id = %s AND id = %s RETURNING id' if column == 'opened_at' else 'UPDATE notification_events SET received_at = COALESCE(received_at, now()) WHERE user_id = %s AND id = %s RETURNING id', (user['id'], event_id)).fetchone()
        if row is None:
            raise HTTPException(404, 'Notification not found')


@app.get('/reports/monthly')
def report_monthly(month: str, card_id: UUID | None = None, user=Depends(current_session)):
    selected_month = reporting_month(month)
    with connect() as db:
        return monthly_report(db, user['id'], selected_month, card_id)


@app.put('/budgets/{month}/{category_id}')
def put_budget(month: str, category_id: UUID, body: BudgetInput, user=Depends(current_session)):
    selected_month = reporting_month(month)
    with connect() as db:
        return save_budget(db, user['id'], category_id, selected_month, body.amount)


@app.delete('/budgets/{month}/{category_id}', status_code=204)
def delete_budget(month: str, category_id: UUID, user=Depends(current_session)):
    selected_month = reporting_month(month)
    with connect() as db:
        require_category(db, user['id'], category_id)
        db.execute('DELETE FROM budgets WHERE user_id = %s AND category_id = %s AND month = %s',
                   (user['id'], category_id, selected_month))


@app.post('/transactions', status_code=201, response_model=TransactionRecord,
          responses={200: {'model': TransactionRecord, 'description': 'Existing matching purchase'}})
def record_purchase(body: PurchaseInput, response: Response, user=Depends(current_session)):
    with connect() as db:
        saved, created = save_purchase(db, user['id'], body)
        response.status_code = 201 if created else 200
        return saved


@app.post('/simulations/purchases', status_code=201, response_model=TransactionRecord)
def simulate_purchase(body: SimulationInput, response: Response, user=Depends(current_session)):
    with connect() as db:
        saved, created = save_purchase(db, user['id'], body, source='simulation', status=body.status)
        response.status_code = 201 if created else 200
        return saved


@app.post('/transactions/{transaction_id}/refunds', status_code=201, response_model=TransactionRecord)
def simulate_refund(transaction_id: UUID, body: RefundInput, response: Response, user=Depends(current_session)):
    with connect() as db:
        saved, created = save_refund(db, user['id'], transaction_id, body)
        response.status_code = 201 if created else 200
        return saved


@app.get('/transactions', response_model=list[TransactionRecord])
def transaction_history(
    limit: Annotated[int, Query(ge=1, le=100)] = 25,
    offset: Annotated[int, Query(ge=0, le=2_147_483_647)] = 0,
    search: Annotated[str, Query(max_length=100)] = '',
    card_id: UUID | None = None,
    category_id: UUID | None = None,
    uncategorized: bool = False,
    status: Literal['approved', 'declined'] | None = None,
    kind: Literal['purchase', 'refund'] | None = None,
    occurred_from: AwareDatetime | None = None,
    occurred_before: AwareDatetime | None = None,
    user=Depends(current_session),
):
    if occurred_from and occurred_before and occurred_from >= occurred_before:
        raise HTTPException(422, 'The end date must follow the start date')
    if category_id is not None and uncategorized:
        raise HTTPException(422, 'Choose a category or uncategorized, not both')
    conditions = ['t.user_id = %s']
    values = [user['id']]
    if search.strip():
        conditions.append('strpos(lower(m.name), lower(%s)) > 0')
        values.append(search.strip())
    for column, value in [('card_id', card_id), ('category_id', category_id), ('status', status), ('kind', kind)]:
        if value is not None:
            conditions.append(f't.{column} = %s')
            values.append(value)
    if uncategorized:
        conditions.append('t.category_id IS NULL')
    if occurred_from is not None:
        conditions.append('t.occurred_at >= %s')
        values.append(occurred_from)
    if occurred_before is not None:
        conditions.append('t.occurred_at < %s')
        values.append(occurred_before)
    with connect() as db:
        return db.execute(
            TRANSACTION_SELECT + ' WHERE ' + ' AND '.join(conditions) + ' ORDER BY t.occurred_at DESC, t.id DESC LIMIT %s OFFSET %s',
            (*values, limit, offset),
        ).fetchall()


@app.patch('/transactions/{transaction_id}/category', response_model=TransactionRecord)
def categorize_transaction(transaction_id: UUID, body: CategoryAssignment, user=Depends(current_session)):
    with connect() as db:
        require_category(db, user['id'], body.category_id)
        updated = db.execute(
            'UPDATE spending_transactions SET category_id = %s WHERE user_id = %s AND id = %s RETURNING id',
            (body.category_id, user['id'], transaction_id),
        ).fetchone()
        if updated is None:
            raise HTTPException(404, 'Transaction not found')
        return db.execute(TRANSACTION_SELECT + ' WHERE t.user_id = %s AND t.id = %s', (user['id'], transaction_id)).fetchone()


@app.get('/transactions/{transaction_id}', response_model=TransactionRecord)
def transaction_detail(transaction_id: UUID, user=Depends(current_session)):
    with connect() as db:
        row = db.execute(
            TRANSACTION_SELECT + ' WHERE t.user_id = %s AND t.id = %s',
            (user['id'], transaction_id),
        ).fetchone()
    if row is None:
        raise HTTPException(404, 'Transaction not found')
    return row


@app.post('/imports/preview')
def preview_csv(body: CsvPreviewInput, user=Depends(current_session)):
    with connect() as db:
        return preview_import(db, user['id'], body)


@app.get('/imports/{batch_id}')
def get_import(batch_id: UUID, user=Depends(current_session)):
    with connect() as db:
        batch = db.execute('SELECT * FROM import_batches WHERE user_id = %s AND id = %s', (user['id'], batch_id)).fetchone()
    if batch is None:
        raise HTTPException(404, 'Import not found')
    return public_batch(batch)


@app.post('/imports/{batch_id}/confirm')
def confirm_csv(batch_id: UUID, body: CsvConfirmation, user=Depends(current_session)):
    with connect() as db:
        return confirm_import(db, user['id'], batch_id, body.preview_token)
