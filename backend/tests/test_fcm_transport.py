import httpx
import pytest

from app.notification_worker import DeliveryError, FcmSender


class Credentials:
    valid = True
    token = 'synthetic-access-token'


def sender():
    instance = FcmSender.__new__(FcmSender)
    instance.project = 'synthetic-project'
    instance.credentials = Credentials()
    return instance


EVENT = {'id': 'event-id', 'transaction_id': 'transaction-id', 'user_id': 'owner-id'}


def test_fcm_payload_is_generic_and_has_stable_tag_and_link_ids(monkeypatch):
    captured = {}
    def post(url, **kwargs):
        captured.update(url=url, **kwargs)
        return httpx.Response(200, json={'name': 'projects/test/messages/accepted'})
    monkeypatch.setattr(httpx, 'post', post)
    assert sender().send('synthetic-device-token', EVENT) == 'projects/test/messages/accepted'
    message = captured['json']['message']
    assert captured['timeout'] == 10
    assert message['data'] == EVENT
    assert message['android']['notification']['tag'] == EVENT['id']
    assert message['notification'] == {'title': 'SpendTrail', 'body': 'New account activity. Open SpendTrail to view it.'}


@pytest.mark.parametrize('status,details,retryable,invalid', [
    (429, [], True, False), (503, [], True, False),
    (400, [{'errorCode': 'INVALID_ARGUMENT'}], False, False),
    (404, [{'errorCode': 'UNREGISTERED'}], False, True),
    (403, [], False, False),
])
def test_fcm_errors_classify_retries_without_revoking_good_tokens(monkeypatch, status, details, retryable, invalid):
    monkeypatch.setattr(httpx, 'post', lambda *args, **kwargs: httpx.Response(status, json={'error': {'details': details}}, headers={'Retry-After': '120'}))
    with pytest.raises(DeliveryError) as caught:
        sender().send('synthetic-device-token', EVENT)
    assert caught.value.retryable is retryable and caught.value.invalid_token is invalid
    assert caught.value.retry_after == 120


def test_network_and_invalid_success_response_remain_retryable(monkeypatch):
    def fail(*args, **kwargs):
        raise httpx.ConnectError('synthetic secret must not appear in errors')
    monkeypatch.setattr(httpx, 'post', fail)
    with pytest.raises(DeliveryError, match='^network_error$'):
        sender().send('synthetic-device-token', EVENT)
    monkeypatch.setattr(httpx, 'post', lambda *args, **kwargs: httpx.Response(200, json={}))
    with pytest.raises(DeliveryError, match='^invalid_provider_response$'):
        sender().send('synthetic-device-token', EVENT)
