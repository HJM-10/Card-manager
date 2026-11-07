from datetime import datetime, timezone
from decimal import Decimal
from typing import Literal
from uuid import UUID, uuid4

from fastapi import HTTPException
from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, field_validator


class PurchaseInput(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    card_id: UUID
    merchant: str = Field(min_length=1, max_length=100)
    amount: str = Field(pattern=r'^[0-9]{1,12}\.[0-9]{2}$')
    occurred_at: AwareDatetime = Field(ge=datetime(2000, 1, 1, tzinfo=timezone.utc), lt=datetime(2101, 1, 1, tzinfo=timezone.utc))
    channel: Literal['online', 'pos']
    source_reference: UUID
    category_id: UUID | None = None

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
    category_id: UUID | None = None
    category: str | None = None


TRANSACTION_SELECT = '''
    SELECT t.id, t.card_id, m.name AS merchant, t.amount, t.occurred_at,
           t.source, t.source_reference, t.kind, t.status, t.channel,
           t.category_id, t.recorded_category_id, c.name AS category
    FROM spending_transactions t
    JOIN merchants m ON (m.user_id, m.id) = (t.user_id, t.merchant_id)
    LEFT JOIN categories c ON (c.user_id, c.id) = (t.user_id, t.category_id)
'''


def require_category(db, user_id, category_id):
    if category_id is not None and not db.execute(
        'SELECT id FROM categories WHERE user_id = %s AND id = %s', (user_id, category_id)
    ).fetchone():
        raise HTTPException(404, 'Category not found')


def matching_purchase(existing, body):
    return (existing['merchant'], existing['amount'], existing['occurred_at'], existing['channel'], existing['recorded_category_id']) == (
        body.merchant, Decimal(body.amount), body.occurred_at, body.channel, body.category_id)


def save_purchase(db, user_id, body, *, source='manual', reference=None, import_batch_id=None):
    """Shared atomic write path; caller owns the transaction/commit boundary."""
    reference = reference if reference is not None else str(body.source_reference)
    card = db.execute('SELECT archived FROM card_profiles WHERE user_id = %s AND id = %s FOR NO KEY UPDATE', (user_id, body.card_id)).fetchone()
    if card is None:
        raise HTTPException(404, 'Card not found')
    existing = db.execute(TRANSACTION_SELECT + ' WHERE t.user_id = %s AND t.card_id = %s AND t.source = %s AND t.source_reference = %s', (user_id, body.card_id, source, reference)).fetchone()
    if existing is not None:
        if not matching_purchase(existing, body):
            raise HTTPException(409, 'This purchase reference is already in use with different details')
        return existing, False
    if card['archived']:
        raise HTTPException(404, 'Card not found')
    require_category(db, user_id, body.category_id)
    db.execute('INSERT INTO merchants (id, user_id, name) VALUES (%s, %s, %s) ON CONFLICT (user_id, name) DO NOTHING', (uuid4(), user_id, body.merchant))
    transaction_id = uuid4()
    db.execute('''INSERT INTO spending_transactions
        (id, user_id, card_id, merchant_id, amount, occurred_at, source, source_reference, kind, status, channel, category_id, recorded_category_id, import_batch_id)
        SELECT %s, user_id, %s, id, %s, %s, %s, %s, 'purchase', 'approved', %s, %s, %s, %s
        FROM merchants WHERE user_id = %s AND name = %s''',
        (transaction_id, body.card_id, Decimal(body.amount), body.occurred_at, source, reference, body.channel, body.category_id, body.category_id, import_batch_id, user_id, body.merchant))
    return db.execute(TRANSACTION_SELECT + ' WHERE t.user_id = %s AND t.id = %s', (user_id, transaction_id)).fetchone(), True
