from typing import Literal
from uuid import UUID, uuid4

from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field


class DeviceInput(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    token: str = Field(min_length=32, max_length=2048, pattern=r'^[!-~]+$')
    platform: Literal['android'] = 'android'


class ObservationInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    action: Literal['received', 'opened']


def cancel_devices(db, user_id, *, device_id=None, session_hashes=None):
    conditions = ['user_id = %s']
    values = [user_id]
    if device_id is not None:
        conditions.append('id = %s')
        values.append(device_id)
    if session_hashes is not None:
        conditions.append('session_hash = ANY(%s)')
        values.append(session_hashes)
    devices = db.execute('SELECT id FROM device_registrations WHERE ' + ' AND '.join(conditions) + ' ORDER BY id FOR UPDATE', values).fetchall()
    for device in devices:
        db.execute('UPDATE device_registrations SET enabled = false, updated_at = now() WHERE id = %s', (device['id'],))
        db.execute("UPDATE notification_events SET status = 'cancelled', lease_id = NULL, lease_until = NULL WHERE device_id = %s AND status IN ('pending', 'processing')", (device['id'],))


def register_device(db, user, device_id, body):
    session = db.execute('SELECT token_hash, biometric_session_id FROM sessions WHERE token_hash = %s AND expires_at > now() FOR UPDATE', (user['token_hash'],)).fetchone()
    if session is None:
        raise HTTPException(401, 'Please sign in again')
    if session['biometric_session_id'] is not None and not db.execute('SELECT id FROM biometric_sessions WHERE id = %s AND NOT revoked AND expires_at > now() FOR UPDATE', (session['biometric_session_id'],)).fetchone():
        raise HTTPException(401, 'Please sign in again')
    # Serializes competing token transfers without allowing another account to
    # edit an existing device ID. Token owners may change accounts on one phone.
    db.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s, 1741))', (body.token,))
    current = db.execute('SELECT user_id FROM device_registrations WHERE id = %s', (device_id,)).fetchone()
    if current is not None and current['user_id'] != user['id']:
        raise HTTPException(404, 'Device not found')
    conflicting = db.execute('SELECT id, user_id FROM device_registrations WHERE token = %s AND enabled AND id <> %s ORDER BY id FOR UPDATE', (body.token, device_id)).fetchall()
    for old in conflicting:
        cancel_devices(db, old['user_id'], device_id=old['id'])
    row = db.execute('''INSERT INTO device_registrations (id, user_id, token, session_hash, platform)
        VALUES (%s, %s, %s, %s, %s) ON CONFLICT (id) DO UPDATE
        SET token = EXCLUDED.token, session_hash = EXCLUDED.session_hash,
            enabled_at = CASE WHEN device_registrations.enabled THEN device_registrations.enabled_at ELSE now() END,
            enabled = true, updated_at = now()
        WHERE device_registrations.user_id = EXCLUDED.user_id
        RETURNING id, enabled, platform''', (device_id, user['id'], body.token, user['token_hash'], body.platform)).fetchone()
    if row is None:
        raise HTTPException(404, 'Device not found')
    return row


def expand_outbox(db, limit=50):
    rows = db.execute('''SELECT o.transaction_id, o.created_at, t.user_id
        FROM transaction_outbox o JOIN spending_transactions t ON t.id = o.transaction_id
        WHERE o.expanded_at IS NULL ORDER BY o.created_at, o.transaction_id
        LIMIT %s FOR UPDATE OF o SKIP LOCKED''', (limit,)).fetchall()
    for row in rows:
        devices = db.execute('''SELECT id FROM device_registrations
            WHERE user_id = %s AND enabled AND enabled_at <= %s''', (row['user_id'], row['created_at'])).fetchall()
        for device in devices:
            db.execute('''INSERT INTO notification_events (id, user_id, transaction_id, device_id)
                VALUES (%s, %s, %s, %s) ON CONFLICT (transaction_id, device_id) DO NOTHING''',
                (uuid4(), row['user_id'], row['transaction_id'], device['id']))
        db.execute('UPDATE transaction_outbox SET expanded_at = now() WHERE transaction_id = %s', (row['transaction_id'],))
    return len(rows)


def claim_event(db):
    db.execute("""UPDATE notification_events SET status = 'failed', last_error = 'delivery_uncertain', lease_id = NULL, lease_until = NULL
        WHERE status = 'processing' AND lease_until <= now() AND attempts >= 5""")
    row = db.execute("""SELECT id, device_id FROM notification_events
        WHERE attempts < 5 AND ((status = 'pending' AND next_attempt_at <= now())
          OR (status = 'processing' AND lease_until <= now()))
        ORDER BY next_attempt_at, created_at, id LIMIT 1 FOR UPDATE SKIP LOCKED""").fetchone()
    if row is None:
        return None
    lease = uuid4()
    db.execute("""UPDATE notification_events SET status = 'processing', attempts = attempts + 1,
        lease_id = %s, lease_until = now() + interval '2 minutes' WHERE id = %s""", (lease, row['id']))
    return {**row, 'lease_id': lease}


EVENT_SELECT = '''SELECT id, transaction_id, device_id, status, attempts, last_error,
    accepted_at, received_at, opened_at, created_at FROM notification_events'''
