import hashlib
import os
import secrets
from datetime import datetime, timezone
from decimal import Decimal
from typing import Annotated, Literal
from uuid import UUID, uuid4

from fastapi import Depends, FastAPI, HTTPException, Query, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from psycopg.errors import UniqueViolation
from pydantic import AwareDatetime, BaseModel, ConfigDict, EmailStr, Field, field_validator
from pwdlib import PasswordHash

from .db import connect

app = FastAPI(title='SpendTrail API', version='0.1.0')
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv('CORS_ORIGINS', 'http://localhost:5173').split(','),
    allow_methods=['GET', 'POST', 'PATCH', 'DELETE'],
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


class CardInput(Input):
    label: str = Field(min_length=1, max_length=50)
    network: Literal['visa', 'mastercard']
    last4: str = Field(pattern=r'^[0-9]{4}$')
    expiry_month: int = Field(ge=1, le=12)
    expiry_year: int = Field(ge=2026, le=2100)


class PurchaseInput(Input):
    card_id: UUID
    merchant: str = Field(min_length=1, max_length=100)
    amount: str = Field(pattern=r'^[0-9]{1,12}\.[0-9]{2}$')
    occurred_at: AwareDatetime = Field(
        ge=datetime(2000, 1, 1, tzinfo=timezone.utc),
        lt=datetime(2101, 1, 1, tzinfo=timezone.utc),
    )
    channel: Literal['online', 'pos']
    source_reference: UUID

    @field_validator('amount')
    @classmethod
    def positive_amount(cls, value):
        if Decimal(value) <= 0:
            raise ValueError('Enter an amount greater than zero')
        return value

    @field_validator('occurred_at', mode='before')
    @classmethod
    def timestamp_string(cls, value):
        if not isinstance(value, str) or 'T' not in value:
            raise ValueError('Use an ISO 8601 date and time with a timezone')
        return value


class TransactionRecord(BaseModel):
    id: UUID
    card_id: UUID
    merchant: str
    amount: Decimal
    currency: Literal['PKR'] = 'PKR'
    occurred_at: AwareDatetime
    source: str
    source_reference: str
    kind: str
    status: str
    channel: str


def digest(token):
    return hashlib.sha256(token.encode()).hexdigest()


def current_session(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)):
    if credentials is None:
        raise HTTPException(401, 'Please sign in', headers={'WWW-Authenticate': 'Bearer'})
    with connect() as db:
        user = db.execute(
            '''SELECT u.id, u.email, u.name, s.token_hash FROM sessions s
               JOIN users u ON u.id = s.user_id
               WHERE s.token_hash = %s AND s.expires_at > now()''',
            (digest(credentials.credentials),),
        ).fetchone()
    if not user:
        raise HTTPException(401, 'Session expired. Please sign in again', headers={'WWW-Authenticate': 'Bearer'})
    return user


def public_user(user):
    return {key: user[key] for key in ('id', 'email', 'name')}


def issue_session(db, user):
    token = secrets.token_urlsafe(32)
    db.execute(
        "INSERT INTO sessions (token_hash, user_id, expires_at) VALUES (%s, %s, now() + interval '12 hours')",
        (digest(token), user['id']),
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
        db.execute('DELETE FROM sessions WHERE token_hash = %s', (user['token_hash'],))


CARD_COLUMNS = 'id, label, network, last4, expiry_month, expiry_year, archived'


@app.get('/cards')
def cards(user=Depends(current_session)):
    with connect() as db:
        return db.execute(f'SELECT {CARD_COLUMNS} FROM card_profiles WHERE user_id = %s AND NOT archived ORDER BY created_at, id', (user['id'],)).fetchall()


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


TRANSACTION_SELECT = '''
    SELECT t.id, t.card_id, m.name AS merchant, t.amount, t.occurred_at,
           t.source, t.source_reference, t.kind, t.status, t.channel
    FROM spending_transactions t
    JOIN merchants m ON (m.user_id, m.id) = (t.user_id, t.merchant_id)
'''


@app.post('/transactions', status_code=201, response_model=TransactionRecord,
          responses={200: {'model': TransactionRecord, 'description': 'Existing matching purchase'}})
def record_purchase(body: PurchaseInput, response: Response, user=Depends(current_session)):
    user_id = user['id']
    reference = str(body.source_reference)
    amount = Decimal(body.amount)
    with connect() as db:
        # Serialize retries on a card and coordinate with card archival.
        card = db.execute(
            'SELECT archived FROM card_profiles WHERE user_id = %s AND id = %s FOR NO KEY UPDATE',
            (user_id, body.card_id),
        ).fetchone()
        if card is None:
            raise HTTPException(404, 'Card not found')

        existing = db.execute(
            TRANSACTION_SELECT + '''
            WHERE t.user_id = %s AND t.card_id = %s
              AND t.source = 'manual' AND t.source_reference = %s
            ''',
            (user_id, body.card_id, reference),
        ).fetchone()
        if existing is not None:
            saved_values = (existing['merchant'], existing['amount'], existing['occurred_at'], existing['channel'])
            if saved_values != (body.merchant, amount, body.occurred_at, body.channel):
                raise HTTPException(409, 'This purchase reference is already in use')
            response.status_code = 200
            return existing
        if card['archived']:
            raise HTTPException(404, 'Card not found')

        db.execute(
            'INSERT INTO merchants (id, user_id, name) VALUES (%s, %s, %s) ON CONFLICT (user_id, name) DO NOTHING',
            (uuid4(), user_id, body.merchant),
        )
        transaction_id = uuid4()
        db.execute(
            '''
            INSERT INTO spending_transactions
                (id, user_id, card_id, merchant_id, amount, occurred_at, source, source_reference, kind, status, channel)
            SELECT %s, user_id, %s, id, %s, %s, 'manual', %s, 'purchase', 'approved', %s
            FROM merchants WHERE user_id = %s AND name = %s
            ''',
            (transaction_id, body.card_id, amount, body.occurred_at, reference, body.channel, user_id, body.merchant),
        )
        return db.execute(
            TRANSACTION_SELECT + ' WHERE t.user_id = %s AND t.id = %s',
            (user_id, transaction_id),
        ).fetchone()


@app.get('/transactions', response_model=list[TransactionRecord])
def transaction_history(
    limit: Annotated[int, Query(ge=1, le=100)] = 25,
    offset: Annotated[int, Query(ge=0, le=2_147_483_647)] = 0,
    user=Depends(current_session),
):
    with connect() as db:
        return db.execute(
            TRANSACTION_SELECT + ' WHERE t.user_id = %s ORDER BY t.occurred_at DESC, t.id DESC LIMIT %s OFFSET %s',
            (user['id'], limit, offset),
        ).fetchall()


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
