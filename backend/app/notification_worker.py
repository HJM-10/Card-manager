"""Run with python -m app.notification_worker [--once]. No simulated sends."""
import argparse
import logging
import os
import random
import time
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

import httpx

from .db import connect
from .notifications import expand_outbox, claim_event

log = logging.getLogger('spendtrail.notifications')


class DeliveryError(Exception):
    def __init__(self, code, *, retryable=True, invalid_token=False, retry_after=0):
        self.code, self.retryable, self.invalid_token, self.retry_after = code, retryable, invalid_token, retry_after
        super().__init__(code)


def retry_after_seconds(value):
    try:
        return max(0, int(value))
    except (ValueError, TypeError):
        try:
            return max(0, int((parsedate_to_datetime(value) - datetime.now(timezone.utc)).total_seconds()))
        except (ValueError, TypeError, OverflowError):
            return 0


class FcmSender:
    def __init__(self):
        self.project = os.getenv('FCM_PROJECT_ID')
        if not self.project:
            raise ValueError('Set FCM_PROJECT_ID before starting the notification worker')
        import google.auth
        from google.auth.transport.requests import Request
        self.credentials, _ = google.auth.default(scopes=['https://www.googleapis.com/auth/firebase.messaging'])
        self.refresh_request = Request()

    def send(self, token, event):
        try:
            if not self.credentials.valid:
                self.credentials.refresh(lambda *args, **kwargs: self.refresh_request(*args, **{**kwargs, 'timeout': 10}))
        except Exception:
            raise DeliveryError('credentials_unavailable') from None
        body = {'message': {
            'token': token,
            # No merchant, amount or account identity appears on the lock screen.
            'notification': {'title': 'SpendTrail', 'body': 'New account activity. Open SpendTrail to view it.'},
            'data': {key: str(event[key]) for key in ('id', 'transaction_id', 'user_id')},
            'android': {'priority': 'high', 'ttl': '86400s', 'notification': {
                'tag': str(event['id']), 'channel_id': 'spendtrail_transactions', 'click_action': 'FLUTTER_NOTIFICATION_CLICK'}},
        }}
        try:
            response = httpx.post(f'https://fcm.googleapis.com/v1/projects/{self.project}/messages:send',
                headers={'Authorization': 'Bearer ' + self.credentials.token}, json=body, timeout=10)
        except httpx.HTTPError:
            raise DeliveryError('network_error') from None
        if response.status_code != 200:
            try:
                details = response.json().get('error', {}).get('details', [])
                invalid = any(d.get('errorCode') == 'UNREGISTERED' for d in details if isinstance(d, dict))
            except (ValueError, AttributeError):
                invalid = False
            if response.status_code == 401:
                self.credentials.token = None
            raise DeliveryError('unregistered' if invalid else f'fcm_http_{response.status_code}',
                retryable=not invalid and response.status_code in (401, 408, 429, 500, 502, 503, 504),
                invalid_token=invalid, retry_after=retry_after_seconds(response.headers.get('Retry-After')))
        try:
            message_id = response.json()['name']
            if not isinstance(message_id, str) or not message_id or len(message_id) > 512:
                raise ValueError()
            return message_id
        except (ValueError, KeyError, TypeError):
            raise DeliveryError('invalid_provider_response') from None


def process_claim(claim, sender, *, connection=connect):
    with connection() as db:
        # Device first everywhere: disable/sign-out waits for any bounded send
        # already in flight, then cancels all future attempts.
        device = db.execute('SELECT * FROM device_registrations WHERE id = %s FOR UPDATE', (claim['device_id'],)).fetchone()
        event = db.execute("SELECT * FROM notification_events WHERE id = %s AND status = 'processing' AND lease_id = %s AND lease_until > now() FOR UPDATE", (claim['id'], claim['lease_id'])).fetchone()
        if event is None:
            return
        if device is None or not device['enabled'] or device['user_id'] != event['user_id']:
            db.execute("UPDATE notification_events SET status = 'cancelled', lease_id = NULL, lease_until = NULL WHERE id = %s", (event['id'],))
            return
        try:
            provider_id = sender.send(device['token'], event)
        except DeliveryError as error:
            if error.invalid_token:
                db.execute('UPDATE device_registrations SET enabled = false, updated_at = now() WHERE id = %s', (device['id'],))
                db.execute("UPDATE notification_events SET status = 'cancelled', lease_id = NULL, lease_until = NULL WHERE device_id = %s AND id <> %s AND status IN ('pending', 'processing')", (device['id'], event['id']))
            retry = error.retryable and event['attempts'] < 5
            delay = max(error.retry_after, min(3600, 60 * 2 ** (event['attempts'] - 1) + random.randint(0, 15)))
            db.execute('''UPDATE notification_events SET status = %s, last_error = %s,
                next_attempt_at = now() + make_interval(secs => %s), lease_id = NULL, lease_until = NULL WHERE id = %s''',
                ('pending' if retry else 'failed', error.code, delay, event['id']))
            log.info('event=%s attempt=%s outcome=%s', event['id'], event['attempts'], 'retry' if retry else 'failed')
        else:
            db.execute("""UPDATE notification_events SET status = 'accepted', provider_message_id = %s,
                accepted_at = now(), last_error = NULL, lease_id = NULL, lease_until = NULL WHERE id = %s""", (provider_id, event['id']))
            log.info('event=%s attempt=%s outcome=accepted', event['id'], event['attempts'])


def run_once(sender, *, connection=connect):
    with connection() as db:
        expanded = expand_outbox(db)
    with connection() as db:
        claim = claim_event(db)
    if claim is not None:
        process_claim(claim, sender, connection=connection)
    return expanded > 0 or claim is not None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--once', action='store_true')
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    try:
        sender = FcmSender()  # Fail before claiming attempts if unconfigured.
    except Exception:
        raise SystemExit('Firebase is not configured. Set FCM_PROJECT_ID and application-default credentials; see docs/NOTIFICATIONS.md.') from None
    while True:
        try:
            busy = run_once(sender)
        except Exception:
            # No raw provider/DB errors: they can contain tokens or credentials.
            log.error('Worker cycle failed; claimed work will recover after its lease expires.')
            if args.once:
                raise SystemExit(1) from None
            busy = False
        if args.once:
            break
        if not busy:
            time.sleep(2)


if __name__ == '__main__':
    main()
