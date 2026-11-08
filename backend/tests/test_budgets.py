from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4

import psycopg
import pytest
from fastapi.testclient import TestClient

from app import db, main
from test_accounts_cards import client, account, purchase_payload, CARD


def setup(client):
    headers = account(client)
    base = purchase_payload(client, headers)
    categories = client.get('/categories', headers=headers).json()
    groceries = next(c['id'] for c in categories if c['name'] == 'Groceries')
    food = next(c['id'] for c in categories if c['name'] == 'Food')
    second = client.post('/cards', headers=headers, json={**CARD, 'last4': '9876', 'label': 'Second'}).json()['id']
    saved = client.post('/transactions', headers=headers, json={**base, 'category_id': groceries}).json()
    for amount, status, timestamp in [
        ('300.00', 'approved', '2026-11-30T23:59:59+05:00'),
        ('900.00', 'declined', '2026-11-10T12:00:00+05:00'),
        ('50.00', 'approved', '2026-12-01T00:00:00+05:00'),
    ]:
        result = client.post('/simulations/purchases', headers=headers, json={**base, 'card_id': second, 'category_id': groceries, 'amount': amount, 'status': status, 'occurred_at': timestamp, 'source_reference': str(uuid4())})
        assert result.status_code == 201, result.text
    refund = {'amount': '250.05', 'occurred_at': '2026-11-06T10:30:00+05:00', 'source_reference': str(uuid4())}
    assert client.post('/transactions/' + saved['id'] + '/refunds', headers=headers, json=refund).status_code == 201
    return headers, groceries, food, base['card_id'], second, saved['id']


def test_budget_report_matches_fixed_totals_across_cards_and_month_boundary(client):
    headers, category, _, first, second, _ = setup(client)
    path = f'/budgets/2026-11/{category}'
    saved = client.put(path, headers=headers, json={'amount': '1500.00'})
    assert saved.status_code == 200, saved.text
    assert client.put(path, headers=headers, json={'amount': '1500.00'}).json()['id'] == saved.json()['id']
    report = client.get('/reports/monthly?month=2026-11', headers=headers).json()
    assert (report['spent'], report['purchases'], report['refunds'], report['transaction_count']) == ('1300.00', '1550.05', '250.05', 4)
    assert report['timezone'] == 'Asia/Karachi' and report['budget_scope'] == 'all_cards'
    assert report['budgets'] == [{'category_id': category, 'category': 'Groceries', 'amount': '1500.00', 'spent': '1300.00', 'remaining': '200.00', 'percent': '86.67', 'over_budget': False}]
    per_card = client.get(f'/reports/monthly?month=2026-11&card_id={first}', headers=headers).json()
    assert per_card['spent'] == '1000.00' and per_card['transaction_count'] == 2
    assert per_card['budgets'] == report['budgets']  # Budgets always cover all cards.
    assert client.get(f'/reports/monthly?month=2026-11&card_id={second}', headers=headers).json()['spent'] == '300.00'
    assert client.get('/reports/monthly?month=2026-12', headers=headers).json()['spent'] == '50.00'


def test_budget_edit_over_budget_remove_and_month_isolation(client):
    headers, category, _, _, _, _ = setup(client)
    path = f'/budgets/2026-11/{category}'
    first = client.put(path, headers=headers, json={'amount': '1500.00'}).json()
    changed = client.put(path, headers=headers, json={'amount': '1000.00'}).json()
    assert first['id'] == changed['id'] and changed['amount'] == '1000.00'
    budget = client.get('/reports/monthly?month=2026-11', headers=headers).json()['budgets'][0]
    assert (budget['remaining'], budget['percent'], budget['over_budget']) == ('-300.00', '130.00', True)
    assert client.put(f'/budgets/2026-12/{category}', headers=headers, json={'amount': '2000.00'}).status_code == 200
    for _ in range(2):
        assert client.delete(path, headers=headers).status_code == 204
    assert client.get('/reports/monthly?month=2026-11', headers=headers).json()['budgets'] == []
    assert client.get('/reports/monthly?month=2026-12', headers=headers).json()['budgets'][0]['amount'] == '2000.00'
    assert len(client.get('/transactions', headers=headers).json()) == 5


def test_negative_month_empty_month_and_recategorization(client):
    headers, category, food, first, _, purchase = setup(client)
    refund = {'amount': '500.00', 'occurred_at': '2026-12-02T00:00:00+05:00', 'source_reference': str(uuid4())}
    assert client.post('/transactions/' + purchase + '/refunds', headers=headers, json=refund).status_code == 201
    client.put(f'/budgets/2026-12/{category}', headers=headers, json={'amount': '1000.00'})
    report = client.get('/reports/monthly?month=2026-12', headers=headers).json()
    assert report['spent'] == '-450.00'
    assert (report['budgets'][0]['remaining'], report['budgets'][0]['percent']) == ('1450.00', '-45.00')
    empty = client.get('/reports/monthly?month=2026-10', headers=headers).json()
    assert empty['spent'] == '0.00' and empty['budgets'] == [] and empty['transaction_count'] == 0
    assert client.patch('/transactions/' + purchase + '/category', headers=headers, json={'category_id': food}).status_code == 200
    report = client.get('/reports/monthly?month=2026-11', headers=headers).json()
    by_category = {row['id']: row['spent'] for row in report['categories']}
    assert by_category[category] == '49.95' and by_category[food] == '1250.05' and report['spent'] == '1300.00'
    assert client.delete('/cards/' + first, headers=headers).status_code == 204
    assert client.get(f'/reports/monthly?month=2026-11&card_id={first}', headers=headers).json()['spent'] == '1000.00'


def test_budget_account_isolation_and_validation(client):
    alice, category, _, card, _, _ = setup(client)
    bob = account(client, 'bob@example.com')
    path = f'/budgets/2026-11/{category}'
    assert client.put(path, headers=bob, json={'amount': '100.00'}).status_code == 404
    assert client.delete(path, headers=bob).status_code == 404
    assert client.get(f'/reports/monthly?month=2026-11&card_id={card}', headers=bob).status_code == 404
    assert client.get('/reports/monthly?month=2026-11', headers=bob).json()['spent'] == '0.00'
    for amount in ['0.00', '-1.00', '1.001', '1e2', 100, '100', '1000000000000.00', 'NaN']:
        assert client.put(path, headers=alice, json={'amount': amount}).status_code == 422
    for month in ['2026-13', '2026-1', '2026-11-01', '1999-12', '2101-01', 'bad']:
        assert client.put(f'/budgets/{month}/{category}', headers=alice, json={'amount': '100.00'}).status_code == 422
        assert client.get('/reports/monthly', params={'month': month}, headers=alice).status_code == 422
    assert client.put(path, headers=alice, json={'amount': '100.00', 'user_id': str(uuid4())}).status_code == 422
    assert client.get('/reports/monthly?month=2026-11').status_code == 401
    assert client.put(path, json={'amount': '100.00'}).status_code == 401
    assert client.delete(path).status_code == 401


def test_concurrent_budget_retries_create_one_row(client):
    headers, category, _, _, _, _ = setup(client)
    path = f'/budgets/2026-11/{category}'
    def save(_):
        with TestClient(main.app) as api:
            result = api.put(path, headers=headers, json={'amount': '1500.00'})
            assert result.status_code == 200
            return result.json()['id']
    with ThreadPoolExecutor(max_workers=2) as executor:
        assert len(set(executor.map(save, range(2)))) == 1
    with db.connect() as conn:
        assert conn.execute('SELECT count(*) AS n FROM budgets').fetchone()['n'] == 1


def test_budget_database_constraints(client):
    headers, category, _, _, _, _ = setup(client)
    bob = account(client, 'bob@example.com')
    bob_id = client.get('/auth/me', headers=bob).json()['id']
    with pytest.raises(psycopg.errors.ForeignKeyViolation):
        with db.connect() as conn:
            conn.execute("INSERT INTO budgets (id, user_id, category_id, month, amount) VALUES (%s, %s, %s, '2026-11-01', 100)", (uuid4(), bob_id, category))
    user = client.get('/auth/me', headers=headers).json()['id']
    for month, amount in [('2026-11-02', '100'), ('2026-11-01', '0'), ('2026-11-01', 'NaN')]:
        with pytest.raises(psycopg.errors.CheckViolation):
            with db.connect() as conn:
                conn.execute('INSERT INTO budgets (id, user_id, category_id, month, amount) VALUES (%s, %s, %s, %s, %s)', (uuid4(), user, category, month, amount))
