import re
from datetime import date
from decimal import Decimal, ROUND_HALF_UP
from uuid import uuid4

from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field, field_validator

from .purchases import require_category


def reporting_month(value: str) -> date:
    if not re.fullmatch(r'(20[0-9]{2}|2100)-(0[1-9]|1[0-2])', value):
        raise HTTPException(422, 'Use a month from 2000-01 through 2100-12 (YYYY-MM)')
    return date.fromisoformat(value + '-01')


class BudgetInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    amount: str = Field(pattern=r'^[0-9]{1,12}\.[0-9]{2}$')

    @field_validator('amount')
    @classmethod
    def positive(cls, value):
        if Decimal(value) <= 0:
            raise ValueError('Enter a budget greater than zero')
        return value


def money(value):
    return format(value, '.2f')


def comparison(amount, spent):
    return {
        'amount': money(amount), 'spent': money(spent),
        'remaining': money(amount - spent),
        'percent': money((spent * 100 / amount).quantize(Decimal('.01'), rounding=ROUND_HALF_UP)),
        'over_budget': spent > amount,
    }


def save_budget(db, user_id, category_id, month, amount):
    require_category(db, user_id, category_id)
    row = db.execute('''INSERT INTO budgets (id, user_id, category_id, month, amount)
        VALUES (%s, %s, %s, %s, %s)
        ON CONFLICT (user_id, category_id, month)
        DO UPDATE SET amount = EXCLUDED.amount, updated_at = now()
        RETURNING id, category_id, month, amount''',
        (uuid4(), user_id, category_id, month, Decimal(amount))).fetchone()
    return {**row, 'amount': money(row['amount']), 'month': month.strftime('%Y-%m')}


def monthly_report(db, user_id, month, card_id=None):
    # One read snapshot keeps category, card, budget and overall totals aligned.
    db.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY')
    cards = db.execute('SELECT id, label, last4, archived FROM card_profiles WHERE user_id = %s ORDER BY created_at, id', (user_id,)).fetchall()
    if card_id is not None and not any(card['id'] == card_id for card in cards):
        raise HTTPException(404, 'Card not found')
    categories = db.execute('''SELECT c.id, c.name, b.amount AS budget_amount
        FROM categories c LEFT JOIN budgets b
          ON b.user_id = c.user_id AND b.category_id = c.id AND b.month = %s
        WHERE c.user_id = %s ORDER BY lower(c.name), c.id''', (month, user_id)).fetchall()
    aggregates = db.execute('''SELECT card_id, category_id, spent, purchases, refunds, transaction_count
        FROM monthly_category_spending WHERE user_id = %s AND month = %s''', (user_id, month)).fetchall()
    selected = [row for row in aggregates if card_id is None or row['card_id'] == card_id]

    def totals(rows):
        # These combine SQL's exact per-card/category aggregates, never floats.
        return {**{key: money(sum((r[key] for r in rows), Decimal('0.00')))
                   for key in ('spent', 'purchases', 'refunds')},
                'transaction_count': sum(r['transaction_count'] for r in rows)}

    category_rows = []
    for category in [*categories, {'id': None, 'name': 'Uncategorized', 'budget_amount': None}]:
        values = totals([row for row in selected if row['category_id'] == category['id']])
        category_rows.append({'id': category['id'], 'name': category['name'], **values})
    budget_rows = []
    for category in categories:
        if category['budget_amount'] is not None:
            spent = sum((row['spent'] for row in aggregates if row['category_id'] == category['id']), Decimal('0.00'))
            budget_rows.append({'category_id': category['id'], 'category': category['name'],
                                **comparison(category['budget_amount'], spent)})
    return {
        'month': month.strftime('%Y-%m'), 'timezone': 'Asia/Karachi', 'currency': 'PKR',
        'card_id': card_id, **totals(selected), 'categories': category_rows,
        'cards': [{**card, **totals([row for row in aggregates if row['card_id'] == card['id']])} for card in cards],
        'budgets': budget_rows, 'budget_scope': 'all_cards',
    }
