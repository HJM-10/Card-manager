import hashlib
import os
import secrets
from datetime import datetime, timezone
from typing import Literal
from uuid import UUID, uuid4

from fastapi import Depends, FastAPI, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from psycopg.errors import UniqueViolation
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator
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
