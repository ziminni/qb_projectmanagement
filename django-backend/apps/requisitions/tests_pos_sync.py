"""Phase 3 / task 3.1b tests: the POS client, its durable worker, read-back.

No test here touches the network. Two fakes cover the two seams:

* `FakeSession` replaces `requests.Session` so the **client's** own rules run for
  real — HTTPS/allowlist enforcement, no cross-origin redirect, one-shot auth
  refresh, id/URL handling, and the redaction of anything written down.
* `FakePosClient` stands in for the client in **worker** tests, where the
  questions are claim-once, retry/backoff, unknown-outcome reconciliation,
  permanent refusals, close coordination and the read-back snapshot.

Routes under test: `GET purchase-orders/{id}/pos-status/` (cached snapshot only,
never a write) and `POST purchase-orders/{id}/pos-sync/` (owner enqueues).
"""

# Pyright here runs without django-stubs, so model managers are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

import copy
import json
import threading
from datetime import timedelta
from decimal import Decimal
from io import StringIO
from unittest import mock

from django.core.management import call_command
from django.db import connections
from django.test import TransactionTestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient

from ..users.models import Role
from . import pos_client, pos_worker
from .models import (
    PosOutboxJob,
    PosOutboxOperation,
    PosOutboxState,
    PosRequestSnapshot,
    PosSyncLog,
    PosSyncStatus,
    PurchaseOrder,
    PurchaseOrderStatus,
)
from .pos_client import (
    PosAuthError,
    PosClient,
    PosConfigError,
    PosNotFound,
    PosRefused,
    PosUnknownOutcome,
    redact_payload,
)
from .tests_procurement import ProcurementCase, ProcurementFixtures

# --- wire bodies the fake store answers with -----------------------------

def import_body(po_no, lines, status='WAITING'):
    """The store's `201`/`200` answer to `POST requests/`."""
    return {
        'id': 11,
        'req_number': 'REQ-000111',
        'cpms_request_id': po_no,
        'status': status,
        'items': [{'code': code, 'quantity': quantity} for code, quantity in lines],
    }


def read_back_body(po_no, lines, status='RELEASED', expected='2500.00'):
    """The store's read-back (`GET requests/{id}/`, and a close's answer)."""
    return {
        'cpms_request_id': po_no,
        'req_number': 'REQ-000111',
        'status': status,
        'decline_reason': '',
        'expected_amount': expected,
        'items': [
            {
                'code': code,
                'requested': requested,
                'released': released,
                'outstanding': str(Decimal(requested) - Decimal(released)),
                'available': True,
                'decline_reason': '',
            }
            for code, requested, released in lines
        ],
    }


class FakePosClient:
    """A scripted stand-in for `PosClient` on the worker's side of the seam.

    Call it with `.script('import', outcome, ...)`: each call pops the next
    outcome, and an `Exception` instance is raised instead of returned. Every
    call is recorded so a test can prove what was (not) sent, and with which
    payload.
    """

    def __init__(self):
        self.calls = []
        self.imports = []
        self.answers = {'import': [], 'read': [], 'close': [], 'payables': []}
        self._lock = threading.Lock()

    def script(self, name, *outcomes):
        self.answers[name].extend(outcomes)
        return self

    def _next(self, name, argument):
        with self._lock:
            self.calls.append((name, argument))
        queue = self.answers[name]
        if not queue:
            raise AssertionError(f'Unexpected POS call: {name}({argument!r})')
        outcome = queue.pop(0)
        if isinstance(outcome, BaseException):
            raise outcome
        return outcome

    def import_request(self, payload, material_request=None):
        with self._lock:
            self.imports.append(copy.deepcopy(payload))
        return self._next('import', payload['cpms_request_id'])

    def read_request(self, cpms_request_id):
        return self._next('read', cpms_request_id)

    def close_request(self, cpms_request_id):
        return self._next('close', cpms_request_id)

    def project_payables(self, cpms_project_id):
        return self._next('payables', cpms_project_id)

    # --- assertions used by several tests -------------------------------
    def names(self):
        return [name for name, _ in self.calls]


# --- HTTP-layer fake for the client's own tests --------------------------

class FakeResponse:
    def __init__(self, status_code, body=None, headers=None, text=''):
        self.status_code = status_code
        self._body = body
        self.headers = headers or {}
        self.text = text

    def json(self):
        if self._body is None:
            raise ValueError('no json body')
        return self._body


class FakeSession:
    """Records every request `PosClient` makes and answers in order."""

    def __init__(self, *responses):
        self.responses = list(responses)
        self.requests = []

    def request(self, method, url, **kwargs):
        self.requests.append({'method': method, 'url': url, **kwargs})
        if not self.responses:
            raise AssertionError(f'Unexpected HTTP call: {method} {url}')
        return self.responses.pop(0)


POS_SETTINGS = {
    'POS_API_BASE_URL': 'https://pos.example.test',
    'POS_API_SERVICE_USERNAME': 'cpms-service',
    'POS_API_SERVICE_PASSWORD': 'service-pass',
    'POS_API_ALLOW_INSECURE_LOCAL': False,
    'POS_API_VERIFY_SSL': True,
    'POS_API_GATEWAY_HEADER_NAME': '',
    'POS_API_GATEWAY_HEADER_VALUE': '',
    'POS_OUTBOX_MAX_ATTEMPTS': 5,
    'POS_OUTBOX_BACKOFF_SECONDS': 30,
    'POS_OUTBOX_BACKOFF_MAX_SECONDS': 3600,
    'POS_OUTBOX_POLL_SECONDS': 30,
    'POS_AUTO_REFRESH_SECONDS': 60,
    'POS_STATUS_STALE_AFTER_SECONDS': 300,
}


@override_settings(**POS_SETTINGS)
class PosClientConfigurationTests(ProcurementCase):
    """Origin rules: HTTPS, allowlist, no credentials in the URL, no URLs at all."""

    def test_a_public_origin_must_use_https(self):
        with self.assertRaises(PosConfigError):
            PosClient(base_url='http://pos.example.test', session=FakeSession())

    def test_plain_http_is_allowed_only_for_a_local_host_and_only_when_enabled(self):
        with override_settings(POS_API_ALLOW_INSECURE_LOCAL=True):
            local = PosClient(base_url='http://127.0.0.1:8000', session=FakeSession())
            self.assertEqual(local.base_url, 'http://127.0.0.1:8000')
            PosClient(base_url='http://host.docker.internal:8000', session=FakeSession())
            with self.assertRaises(PosConfigError):
                PosClient(base_url='http://pos.example.test', session=FakeSession())

    def test_a_url_with_credentials_or_a_query_is_refused(self):
        for bad in (
            'https://user:pass@pos.example.test',
            'https://pos.example.test/?next=http://evil.test',
            'https://pos.example.test/#fragment',
        ):
            with self.subTest(url=bad), self.assertRaises(PosConfigError):
                PosClient(base_url=bad, session=FakeSession())

    def test_a_request_id_is_an_id_and_never_a_url(self):
        session = FakeSession()
        client = PosClient(session=session)
        for bad in ('../admin/', 'PO-2026-0001/close', 'PO 1', 'x' * 200, ''):
            with self.subTest(value=bad), self.assertRaises(PosConfigError):
                client.read_request(bad)
        self.assertEqual(session.requests, [])

    def test_the_gateway_header_is_sent_when_configured(self):
        session = FakeSession(
            FakeResponse(200, {'access': 'jwt-one', 'refresh': 'refresh-one'}),
            FakeResponse(200, {'cpms_request_id': 'PO-1', 'items': []}),
        )
        with override_settings(
            POS_API_GATEWAY_HEADER_NAME='X-Store-Gateway',
            POS_API_GATEWAY_HEADER_VALUE='let-me-in',
        ):
            client = PosClient(session=session)
            client.read_request('PO-1')
        headers = session.requests[-1]['headers']
        self.assertEqual(headers['X-Store-Gateway'], 'let-me-in')
        self.assertIn('Authorization', headers)


@override_settings(**POS_SETTINGS)
class PosClientTokenReuseTests(ProcurementCase):
    """Every call builds a new client; they must share one store sign-in.

    The tunnel gateway allows about six sign-ins a minute. Signing in per call
    locked CPMS out (HTTP 429) as soon as a screen read several projects.
    """

    def setUp(self):
        super().setUp()
        pos_client.forget_shared_tokens()
        self.addCleanup(pos_client.forget_shared_tokens)

    def test_new_clients_reuse_the_first_sign_in(self):
        session = FakeSession(
            FakeResponse(200, {'access': 'jwt-one', 'refresh': 'refresh-one'}),
            FakeResponse(200, {'cpms_request_id': 'PO-1', 'items': []}),
            FakeResponse(200, {'cpms_request_id': 'PO-2', 'items': []}),
        )
        with mock.patch.object(pos_client.requests, 'Session', return_value=session):
            PosClient().read_request('PO-1')
            PosClient().read_request('PO-2')

        paths = [r['url'].removeprefix('https://pos.example.test') for r in session.requests]
        self.assertEqual(paths.count(pos_client.LOGIN_PATH), 1)
        self.assertEqual(session.requests[-1]['headers']['Authorization'], 'Bearer jwt-one')

    def test_an_expired_shared_token_is_refreshed_once_for_everyone(self):
        session = FakeSession(
            FakeResponse(200, {'access': 'jwt-one', 'refresh': 'refresh-one'}),
            FakeResponse(200, {'cpms_request_id': 'PO-1', 'items': []}),
            FakeResponse(401, {}),
            FakeResponse(200, {'access': 'jwt-two'}),
            FakeResponse(200, {'cpms_request_id': 'PO-2', 'items': []}),
            FakeResponse(200, {'cpms_request_id': 'PO-3', 'items': []}),
        )
        with mock.patch.object(pos_client.requests, 'Session', return_value=session):
            PosClient().read_request('PO-1')
            PosClient().read_request('PO-2')
            PosClient().read_request('PO-3')

        self.assertEqual(session.requests[-1]['headers']['Authorization'], 'Bearer jwt-two')
        self.assertEqual(session.responses, [])

    def test_a_client_with_its_own_session_keeps_its_own_sign_in(self):
        pos_client.forget_shared_tokens()
        first = FakeSession(
            FakeResponse(200, {'access': 'jwt-one', 'refresh': 'r'}),
            FakeResponse(200, {'cpms_request_id': 'PO-1', 'items': []}),
        )
        second = FakeSession(
            FakeResponse(200, {'access': 'jwt-two', 'refresh': 'r'}),
            FakeResponse(200, {'cpms_request_id': 'PO-1', 'items': []}),
        )
        PosClient(session=first).read_request('PO-1')
        PosClient(session=second).read_request('PO-1')

        self.assertEqual(second.requests[-1]['headers']['Authorization'], 'Bearer jwt-two')


@override_settings(**POS_SETTINGS)
class PosClientTransportTests(ProcurementCase):
    """Authentication, redirects, refusals and unreadable bodies."""

    def client_with(self, *responses):
        session = FakeSession(*responses)
        return PosClient(session=session), session

    def test_the_service_account_logs_in_once_and_reuses_its_token(self):
        client, session = self.client_with(
            FakeResponse(200, {'access': 'jwt-one', 'refresh': 'refresh-one'}),
            FakeResponse(200, {'cpms_request_id': 'PO-1', 'items': []}),
            FakeResponse(200, {'cpms_request_id': 'PO-2', 'items': []}),
        )
        client.read_request('PO-1')
        client.read_request('PO-2')
        paths = [request['url'] for request in session.requests]
        self.assertEqual(
            paths,
            [
                'https://pos.example.test/api/v1/auth/login/',
                'https://pos.example.test/api/v1/integration/cpms/requests/PO-1/',
                'https://pos.example.test/api/v1/integration/cpms/requests/PO-2/',
            ],
        )
        self.assertEqual(
            session.requests[1]['headers']['Authorization'], 'Bearer jwt-one',
        )

    def test_a_401_refreshes_once_and_retries_the_same_call(self):
        client, session = self.client_with(
            FakeResponse(200, {'access': 'jwt-one', 'refresh': 'refresh-one'}),
            FakeResponse(401, {'detail': 'expired'}),
            FakeResponse(200, {'access': 'jwt-two', 'refresh': 'refresh-two'}),
            FakeResponse(200, {'cpms_request_id': 'PO-1', 'items': []}),
        )
        self.assertEqual(client.read_request('PO-1')['cpms_request_id'], 'PO-1')
        self.assertEqual(
            [request['url'].rsplit('/api/v1/', 1)[-1] for request in session.requests],
            ['auth/login/', 'integration/cpms/requests/PO-1/',
             'auth/refresh/', 'integration/cpms/requests/PO-1/'],
        )
        self.assertEqual(
            session.requests[-1]['headers']['Authorization'], 'Bearer jwt-two',
        )

    def test_a_second_401_is_an_auth_error_and_stops(self):
        client, session = self.client_with(
            FakeResponse(200, {'access': 'jwt-one', 'refresh': 'refresh-one'}),
            FakeResponse(401, {}),
            FakeResponse(200, {'access': 'jwt-two', 'refresh': 'refresh-two'}),
            FakeResponse(401, {}),
        )
        with self.assertRaises(PosAuthError):
            client.read_request('PO-1')
        self.assertEqual(len(session.requests), 4)

    def test_a_redirect_is_not_followed(self):
        client, session = self.client_with(
            FakeResponse(200, {'access': 'jwt-one', 'refresh': 'refresh-one'}),
            FakeResponse(302, None, headers={'Location': 'https://evil.test/steal'}),
        )
        with self.assertRaises(PosUnknownOutcome):
            client.import_request({'cpms_request_id': 'PO-1', 'items': []})
        self.assertEqual(len(session.requests), 2)
        self.assertFalse(session.requests[-1].get('allow_redirects', True))

    def test_a_4xx_refusal_carries_its_code_and_a_404_is_its_own_error(self):
        client, _ = self.client_with(
            FakeResponse(200, {'access': 'jwt-one', 'refresh': 'refresh-one'}),
            FakeResponse(409, {'code': 'TOKEN_TAKEN', 'detail': 'spoken for'}),
        )
        with self.assertRaises(PosRefused) as caught:
            client.import_request({'cpms_request_id': 'PO-1', 'items': []})
        self.assertEqual(caught.exception.code, 'TOKEN_TAKEN')
        self.assertEqual(caught.exception.status_code, 409)

        client, _ = self.client_with(
            FakeResponse(200, {'access': 'jwt-one', 'refresh': 'refresh-one'}),
            FakeResponse(404, {'code': 'REQUEST_NOT_FOUND', 'detail': 'gone'}),
        )
        with self.assertRaises(PosNotFound):
            client.read_request('PO-1')

    def test_a_5xx_or_an_unreadable_2xx_is_an_unknown_outcome(self):
        client, _ = self.client_with(
            FakeResponse(200, {'access': 'jwt-one', 'refresh': 'refresh-one'}),
            FakeResponse(502, None, text='<html>bad gateway</html>'),
        )
        with self.assertRaises(PosUnknownOutcome):
            client.import_request({'cpms_request_id': 'PO-1', 'items': []})

        client, _ = self.client_with(
            FakeResponse(200, {'access': 'jwt-one', 'refresh': 'refresh-one'}),
            FakeResponse(201, None, text='not json'),
        )
        with self.assertRaises(PosUnknownOutcome):
            client.import_request({'cpms_request_id': 'PO-1', 'items': []})


class RedactionTests(ProcurementCase):
    def test_redact_payload_hides_the_token_and_the_credentials(self):
        payload = {
            'cpms_request_id': 'PO-2026-0001',
            'token': '8b1a1b1e-1111-2222-3333-444455556666',
            'items': [{'code': 'CEM-40KG', 'quantity': '10.00'}],
            'project': {'cpms_project_id': 'PRJ-A', 'name': 'Tower A', 'payer': 7},
        }
        redacted = redact_payload(payload)
        assert isinstance(redacted, dict)
        self.assertEqual(redacted['token'], '***')
        self.assertEqual(redacted['cpms_request_id'], 'PO-2026-0001')
        self.assertEqual(redacted['items'], payload['items'])
        # The original is untouched: callers keep the real payload.
        self.assertNotEqual(payload['token'], '***')
        # ... and nothing nested hides a secret either.
        self.assertNotIn('8b1a1b1e', repr(redacted))


class PosWorkflowCase(ProcurementCase):
    """Fixtures plus one own-store order with its durable import job."""

    def setUp(self):
        super().setUp()
        _, response = self.place_order()
        self.assertEqual(response.status_code, 201, response.data)
        self.order = PurchaseOrder.objects.get(pk=response.data['id'])
        self.import_job = self.order.outbox_jobs.get(operation=PosOutboxOperation.IMPORT)
        self.po_no = self.order.po_no
        self.token = str(self.order.pos_token)

    def sent_lines(self):
        return [(line['code'], line['quantity']) for line in self.import_job.payload['items']]

    def run_worker(self, fake, now=None, limit=None):
        return pos_worker.run_once(
            client=fake, limit=limit, now=now or timezone.now(),
        )


class ImportJobTests(PosWorkflowCase):
    def test_the_payer_is_the_suppliers_current_one_at_send_time(self):
        # A payer fixed in the supplier list (or by seed_demo) must heal an order
        # whose stored payload still carries the old, refused payer.
        self.own_store.pos_payer_id = 9
        self.own_store.save(update_fields=['pos_payer_id'])
        fake = FakePosClient().script('import', import_body(self.po_no, self.sent_lines()))
        self.run_worker(fake)

        self.assertEqual(fake.imports[0]['project']['payer'], 9)
        job = PosOutboxJob.objects.get(pk=self.import_job.pk)
        self.assertEqual(job.payload['project']['payer'], 9)

    def test_a_201_marks_the_order_synced_and_snapshots_the_status(self):
        fake = FakePosClient().script('import', import_body(self.po_no, self.sent_lines()))
        processed = self.run_worker(fake)

        self.assertEqual(processed, 1)
        order = PurchaseOrder.objects.get(pk=self.order.pk)
        self.assertEqual(order.pos_sync_status, PosSyncStatus.SYNCED)
        job = PosOutboxJob.objects.get(pk=self.import_job.pk)
        self.assertEqual(job.state, PosOutboxState.DONE)
        self.assertEqual(job.attempts, 1)
        self.assertEqual(job.last_error, '')
        snapshot = PosRequestSnapshot.objects.get(purchase_order=self.order)
        self.assertEqual(snapshot.pos_status, 'WAITING')
        self.assertFalse(snapshot.stale)
        self.assertIsNotNone(snapshot.last_checked_at)
        # The worker sent the stored payload, with the stored token.
        self.assertEqual(fake.imports[0]['token'], self.token)
        self.assertEqual(fake.imports[0]['cpms_request_id'], self.po_no)

    def test_a_200_duplicate_also_marks_the_order_synced(self):
        fake = FakePosClient().script(
            'import', import_body(self.po_no, self.sent_lines(), status='ACCEPTED'),
        )
        self.run_worker(fake)
        order = PurchaseOrder.objects.get(pk=self.order.pk)
        self.assertEqual(order.pos_sync_status, PosSyncStatus.SYNCED)
        self.assertEqual(
            PosRequestSnapshot.objects.get(purchase_order=order).pos_status, 'ACCEPTED',
        )

    def test_a_transient_failure_keeps_the_order_pending_and_backs_off(self):
        fake = FakePosClient().script('import', PosUnknownOutcome('timed out'))
        now = timezone.now()
        # The unknown outcome triggers a reconcile read that also fails.
        fake.script('read', PosUnknownOutcome('timed out again'))
        self.run_worker(fake, now=now)

        order = PurchaseOrder.objects.get(pk=self.order.pk)
        self.assertEqual(order.pos_sync_status, PosSyncStatus.PENDING_SYNC)
        job = PosOutboxJob.objects.get(pk=self.import_job.pk)
        self.assertEqual(job.state, PosOutboxState.PENDING)
        self.assertEqual(job.attempts, 1)
        self.assertGreater(job.next_attempt_at, now)
        self.assertIn('unknown', job.last_error.lower())
        self.assertNotIn(self.token, job.last_error)

    @override_settings(POS_OUTBOX_MAX_ATTEMPTS=5)
    def test_an_exhausted_import_counts_each_attempt_once_and_notes_the_same_count(self):
        fake = FakePosClient()
        start = timezone.now()
        for attempt in range(5):
            fake.script('import', PosUnknownOutcome('store is down'))
            fake.script('read', PosUnknownOutcome('store is down'))
            self.run_worker(fake, now=start + timedelta(minutes=30 * attempt))

        self.import_job.refresh_from_db()
        self.assertEqual(self.import_job.state, PosOutboxState.FAILED)
        self.assertEqual(self.import_job.attempts, 5)
        self.assertIn('Gave up after 5 attempts', self.import_job.last_error)
        snapshot = PosRequestSnapshot.objects.get(purchase_order=self.order)
        self.assertEqual(snapshot.detail, self.import_job.last_error)
        self.assertTrue(snapshot.stale)
        self.assertEqual(
            PurchaseOrder.objects.get(pk=self.order.pk).pos_sync_status,
            PosSyncStatus.FAILED,
        )

    def test_a_retry_reuses_the_exact_same_payload_and_token(self):
        fake = FakePosClient().script(
            'import',
            PosUnknownOutcome('timed out'),
            import_body(self.po_no, self.sent_lines()),
        )
        fake.script('read', PosNotFound('REQUEST_NOT_FOUND', 404))
        now = timezone.now()
        self.run_worker(fake, now=now)
        # Before the backoff expires the job is not due.
        self.assertEqual(self.run_worker(fake, now=now), 0)
        self.assertEqual(len(fake.imports), 1)
        # After it, the same identity goes out again — same payload, same token.
        self.run_worker(fake, now=now + timedelta(minutes=5))

        self.assertEqual(len(fake.imports), 2)
        self.assertEqual(fake.imports[0], fake.imports[1])
        self.assertEqual(fake.imports[1]['items'], self.import_job.payload['items'])
        self.assertEqual(fake.imports[1]['token'], self.token)
        order = PurchaseOrder.objects.get(pk=self.order.pk)
        self.assertEqual(order.pos_sync_status, PosSyncStatus.SYNCED)
        self.assertEqual(order.pos_token, self.order.pos_token)

    def test_an_unknown_outcome_that_the_store_did_store_is_reconciled_not_resent(self):
        fake = FakePosClient().script('import', PosUnknownOutcome('connection reset'))
        fake.script('read', read_back_body(
            self.po_no,
            [(code, '10.00', '0.00') for code, _ in self.sent_lines()],
            status='WAITING',
        ))
        self.run_worker(fake)

        self.assertEqual(fake.names(), ['import', 'read'])
        order = PurchaseOrder.objects.get(pk=self.order.pk)
        self.assertEqual(order.pos_sync_status, PosSyncStatus.SYNCED)
        job = PosOutboxJob.objects.get(pk=self.import_job.pk)
        self.assertEqual(job.state, PosOutboxState.DONE)
        self.assertEqual(
            PosRequestSnapshot.objects.get(purchase_order=order).pos_status, 'WAITING',
        )

    def test_a_404_after_an_unknown_outcome_retries_the_same_identity_only(self):
        fake = FakePosClient().script('import', PosUnknownOutcome('timed out'))
        fake.script('read', PosNotFound('REQUEST_NOT_FOUND', 404))
        now = timezone.now()
        self.run_worker(fake, now=now)
        order = PurchaseOrder.objects.get(pk=self.order.pk)
        # Nothing was created, so the identity stays exactly as minted.
        self.assertEqual(order.po_no, self.po_no)
        self.assertEqual(order.pos_token, self.order.pos_token)

        fake.script('import', import_body(self.po_no, self.sent_lines()))
        self.run_worker(fake, now=now + timedelta(minutes=5))
        self.assertEqual(fake.imports[-1]['cpms_request_id'], self.po_no)
        self.assertEqual(fake.imports[-1]['token'], self.token)
        self.assertEqual(
            PurchaseOrder.objects.get(pk=self.order.pk).pos_sync_status,
            PosSyncStatus.SYNCED,
        )

    def test_token_taken_is_permanent_and_never_regenerates_the_token(self):
        fake = FakePosClient().script(
            'import', PosRefused('TOKEN_TAKEN', 409, 'This token is taken.'),
        )
        self.run_worker(fake)
        order = PurchaseOrder.objects.get(pk=self.order.pk)
        self.assertEqual(order.pos_sync_status, PosSyncStatus.FAILED)
        job = PosOutboxJob.objects.get(pk=self.import_job.pk)
        self.assertEqual(job.state, PosOutboxState.FAILED)
        self.assertIn('TOKEN_TAKEN', job.last_error)
        self.assertEqual(order.pos_token, self.order.pos_token)

        # No automatic retry, ever.
        self.assertEqual(self.run_worker(fake, now=timezone.now() + timedelta(days=1)), 0)
        self.assertEqual(len(fake.imports), 1)

    def test_a_validation_refusal_is_permanent_and_needs_review(self):
        fake = FakePosClient().script(
            'import',
            PosRefused('UNKNOWN_MATERIAL', 400, 'Unknown material code(s): CEM-40KG.'),
        )
        self.run_worker(fake)
        job = PosOutboxJob.objects.get(pk=self.import_job.pk)
        self.assertEqual(job.state, PosOutboxState.FAILED)
        self.assertIn('UNKNOWN_MATERIAL', job.last_error)
        self.assertEqual(
            PurchaseOrder.objects.get(pk=self.order.pk).pos_sync_status,
            PosSyncStatus.FAILED,
        )
        snapshot = PosRequestSnapshot.objects.get(purchase_order=self.order)
        self.assertTrue(snapshot.stale)
        self.assertIn('UNKNOWN_MATERIAL', snapshot.detail)

    def test_a_body_that_names_other_lines_is_blocked_not_trusted(self):
        fake = FakePosClient().script(
            'import',
            import_body(self.po_no, [('SOMETHING-ELSE', '99.00')]),
        )
        self.run_worker(fake)
        job = PosOutboxJob.objects.get(pk=self.import_job.pk)
        self.assertEqual(job.state, PosOutboxState.FAILED)
        self.assertIn('different lines', job.last_error)
        self.assertEqual(
            PurchaseOrder.objects.get(pk=self.order.pk).pos_sync_status,
            PosSyncStatus.FAILED,
        )

    def test_a_body_that_names_another_request_is_blocked(self):
        fake = FakePosClient().script(
            'import', import_body('PO-9999-0001', self.sent_lines()),
        )
        self.run_worker(fake)
        job = PosOutboxJob.objects.get(pk=self.import_job.pk)
        self.assertEqual(job.state, PosOutboxState.FAILED)

    def test_the_worker_never_writes_the_token_anywhere_it_can_be_read(self):
        fake = FakePosClient().script(
            'import', import_body(self.po_no, self.sent_lines()),
        )
        self.run_worker(fake)
        for log in PosSyncLog.objects.all():
            self.assertNotIn(self.token, repr(log.request_payload))
            self.assertNotIn('Bearer', repr(log.request_payload))
        job = PosOutboxJob.objects.get(pk=self.import_job.pk)
        self.assertNotIn(self.token, job.last_error)
        self.assertNotIn(self.token, repr(job.payload))


class CancelAndCloseTests(PosWorkflowCase):
    def cancel(self):
        self.act_as(self.owner, Role.OWNER)
        response = self.client.post(f'/api/v1/purchase-orders/{self.order.pk}/cancel/')
        self.assertEqual(response.status_code, 200, response.data)
        return response

    def test_cancelling_before_the_import_cancels_the_job_and_sends_nothing(self):
        self.cancel()
        job = PosOutboxJob.objects.get(pk=self.import_job.pk)
        self.assertEqual(job.state, PosOutboxState.CANCELLED)

        fake = FakePosClient()
        self.assertEqual(self.run_worker(fake), 0)
        self.assertEqual(fake.calls, [])

    def test_cancelling_a_synced_order_queues_a_close_that_the_worker_delivers(self):
        fake = FakePosClient().script(
            'import', import_body(self.po_no, self.sent_lines(), status='PARTIAL'),
        )
        self.run_worker(fake)
        self.cancel()

        close_job = PosOutboxJob.objects.get(
            purchase_order=self.order, operation=PosOutboxOperation.CLOSE,
        )
        self.assertEqual(close_job.state, PosOutboxState.PENDING)
        self.assertEqual(close_job.payload, {'cpms_request_id': self.po_no})

        fake.script('close', read_back_body(
            self.po_no, [(code, '10.00', '10.00') for code, _ in self.sent_lines()],
            status='CLOSED', expected='0.00',
        ))
        self.run_worker(fake)
        close_job.refresh_from_db()
        self.assertEqual(close_job.state, PosOutboxState.DONE)
        self.assertEqual(fake.names()[-1], 'close')
        snapshot = PosRequestSnapshot.objects.get(purchase_order=self.order)
        self.assertEqual(snapshot.pos_status, 'CLOSED')
        self.assertFalse(snapshot.stale)

    def test_a_close_for_a_request_the_store_never_stored_is_done_not_retried(self):
        self.run_worker(FakePosClient().script(
            'import', import_body(self.po_no, self.sent_lines()),
        ))
        self.cancel()
        fake = FakePosClient().script('close', PosNotFound('REQUEST_NOT_FOUND', 404))
        self.run_worker(fake)
        close_job = PosOutboxJob.objects.get(
            purchase_order=self.order, operation=PosOutboxOperation.CLOSE,
        )
        self.assertEqual(close_job.state, PosOutboxState.DONE)
        self.assertEqual(len(fake.calls), 1)

    def test_a_close_waits_for_an_import_another_worker_is_sending(self):
        self.run_worker(FakePosClient().script(
            'import', import_body(self.po_no, self.sent_lines()),
        ))
        self.cancel()
        fake = FakePosClient()
        # A worker mid-import holds that row; `nowait` cannot see it from inside
        # this test's single transaction, so the seam is stubbed: the close must
        # step aside instead of closing a request that may go live afterwards.
        with mock.patch.object(pos_worker, '_import_in_flight', return_value=True):
            self.run_worker(fake)

        close_job = PosOutboxJob.objects.get(
            purchase_order=self.order, operation=PosOutboxOperation.CLOSE,
        )
        self.assertEqual(close_job.state, PosOutboxState.PENDING)
        self.assertEqual(close_job.attempts, 1)
        self.assertIn('still running', close_job.last_error)
        self.assertEqual(fake.calls, [])

    def test_the_worker_drops_an_import_whose_order_was_cancelled_mid_flight(self):
        # The cancel committed while a worker was holding the import job: the
        # import must never create a fresh live request afterwards.
        PurchaseOrder.objects.filter(pk=self.order.pk).update(
            status=PurchaseOrderStatus.CANCELLED,
        )
        PosOutboxJob.objects.create(
            purchase_order=self.order,
            operation=PosOutboxOperation.CLOSE,
            idempotency_key=f'close:{self.order.pos_request_id}',
            payload={'cpms_request_id': self.po_no},
        )
        fake = FakePosClient().script('close', read_back_body(
            self.po_no, [(code, '10.00', '0.00') for code, _ in self.sent_lines()],
            status='CLOSED', expected='0.00',
        ))
        self.run_worker(fake)

        import_job = PosOutboxJob.objects.get(pk=self.import_job.pk)
        self.assertEqual(import_job.state, PosOutboxState.CANCELLED)
        self.assertNotIn('import', fake.names())
        close_job = PosOutboxJob.objects.get(
            purchase_order=self.order, operation=PosOutboxOperation.CLOSE,
        )
        self.assertEqual(close_job.state, PosOutboxState.DONE)


class FailedCloseRecoveryTests(PosWorkflowCase):
    """A close that gave up stays visible and can be re-armed by the owner.

    The scenario this design exists for: the store is down for ~8 minutes at
    cancel time. After the bounded attempts the close is `failed`, so the UI
    must still say a close is owed, and the owner must have a route to retry
    only that close — never a new import.
    """

    NOTE = 'The store may still hold this request. Retry the close.'

    def sync(self):
        fake = FakePosClient().script('import', import_body(self.po_no, self.sent_lines()))
        self.run_worker(fake)

    def cancel(self):
        self.act_as(self.owner, Role.OWNER)
        response = self.client.post(f'/api/v1/purchase-orders/{self.order.pk}/cancel/')
        self.assertEqual(response.status_code, 200, response.data)

    def close_job(self):
        return PosOutboxJob.objects.get(
            purchase_order=self.order, operation=PosOutboxOperation.CLOSE,
        )

    def exhaust_close(self):
        """The store is unreachable for every attempt, so the close gives up."""
        self.sync()
        self.cancel()
        fake = FakePosClient()
        for _ in range(5):
            fake.script('close', PosUnknownOutcome('store is down'))
            fake.script('read', PosUnknownOutcome('store is down'))
        start = timezone.now()
        for attempt in range(5):
            self.run_worker(fake, now=start + timedelta(minutes=30 * attempt))
        return self.close_job()

    def status(self):
        self.act_as(self.owner, Role.OWNER)
        response = self.client.get(f'/api/v1/purchase-orders/{self.order.pk}/pos-status/')
        self.assertEqual(response.status_code, 200, response.data)
        return response.data

    def post_sync(self):
        self.act_as(self.owner, Role.OWNER)
        return self.client.post(f'/api/v1/purchase-orders/{self.order.pk}/pos-sync/')

    @override_settings(POS_OUTBOX_MAX_ATTEMPTS=5)
    def test_a_gave_up_close_is_failed_and_keeps_a_stale_note_in_the_snapshot(self):
        close_job = self.exhaust_close()

        self.assertEqual(close_job.state, PosOutboxState.FAILED)
        self.assertEqual(close_job.attempts, 5)
        self.assertIn('Gave up after 5 attempts', close_job.last_error)
        snapshot = PosRequestSnapshot.objects.get(purchase_order=self.order)
        self.assertTrue(snapshot.stale)
        self.assertIn('Gave up after 5 attempts', snapshot.detail)

    def test_pos_status_still_shows_a_gave_up_close_as_needing_review(self):
        self.exhaust_close()
        data = self.status()

        self.assertFalse(data['close_pending'])
        self.assertTrue(data['close_needs_review'])
        self.assertIn(self.NOTE, data['detail'])
        # No credential or operation id rides along with the new field.
        body = json.dumps(data, default=str)
        self.assertNotIn(self.token, body)
        self.assertNotIn(str(self.order.pos_request_id), body)

    def test_pos_sync_re_arms_only_the_failed_close_and_the_next_run_clears_it(self):
        self.exhaust_close()
        imports_before = PosOutboxJob.objects.filter(
            purchase_order=self.order, operation=PosOutboxOperation.IMPORT,
        ).count()

        response = self.post_sync()
        self.assertEqual(response.status_code, 202, response.data)
        self.assertTrue(response.data['close_pending'])
        self.assertFalse(response.data['close_needs_review'])

        close_job = self.close_job()
        self.assertEqual(close_job.state, PosOutboxState.PENDING)
        self.assertEqual(close_job.attempts, 0)
        # Only the close was re-armed: no second import, no new import job.
        self.assertEqual(
            PosOutboxJob.objects.filter(
                purchase_order=self.order, operation=PosOutboxOperation.IMPORT,
            ).count(),
            imports_before,
        )
        self.assertEqual(
            PosOutboxJob.objects.get(pk=self.import_job.pk).state, PosOutboxState.DONE,
        )
        self.assertEqual(
            PurchaseOrder.objects.get(pk=self.order.pk).pos_sync_status,
            PosSyncStatus.SYNCED,
        )

        fake = FakePosClient().script('close', read_back_body(
            self.po_no, [(code, '10.00', '0.00') for code, _ in self.sent_lines()],
            status='CLOSED', expected='0.00',
        ))
        self.run_worker(fake)

        self.assertEqual(self.close_job().state, PosOutboxState.DONE)
        self.assertNotIn('import', fake.names())
        data = self.status()
        self.assertFalse(data['close_pending'])
        self.assertFalse(data['close_needs_review'])
        self.assertNotIn(self.NOTE, data['detail'])

    def test_pos_sync_on_a_cancelled_order_without_a_failed_close_still_refuses(self):
        # Never sent: the cancel drops the import and there is nothing to close.
        self.cancel()
        response = self.post_sync()
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('cancelled', str(response.data['detail']).lower())

    def test_pos_sync_refuses_while_a_close_is_still_pending(self):
        self.sync()
        self.cancel()
        response = self.post_sync()
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('cancelled', str(response.data['detail']).lower())

    def test_only_the_owner_may_re_arm_a_failed_close_and_scope_still_hides_it(self):
        self.exhaust_close()
        for user, role in (
            (self.engineer, Role.SITE_ENGINEER),
            (self.accountant, Role.ACCOUNTANT),
            (self.admin, Role.ADMIN),
        ):
            with self.subTest(role=role):
                self.act_as(user, role)
                self.assertEqual(
                    self.client.post(
                        f'/api/v1/purchase-orders/{self.order.pk}/pos-sync/',
                    ).status_code,
                    403,
                )

        self.act_as(self.other_owner, Role.OWNER)
        self.assertEqual(
            self.client.post(
                f'/api/v1/purchase-orders/{self.order.pk}/pos-sync/',
            ).status_code,
            404,
        )
        self.assertEqual(
            self.client.get(
                f'/api/v1/purchase-orders/{self.order.pk}/pos-status/',
            ).status_code,
            404,
        )
        # The failed close is still exactly where it was.
        self.assertEqual(self.close_job().state, PosOutboxState.FAILED)


class RefreshJobTests(PosWorkflowCase):
    def sync(self, fake=None):
        fake = fake or FakePosClient()
        fake.script('import', import_body(self.po_no, self.sent_lines()))
        self.run_worker(fake)
        return fake

    def post_sync(self, order=None, user=None, role=Role.OWNER):
        self.act_as(user or self.owner, role)
        return self.client.post(
            f'/api/v1/purchase-orders/{(order or self.order).pk}/pos-sync/',
        )

    def test_pos_sync_on_a_synced_order_queues_a_read_back(self):
        self.sync()
        response = self.post_sync()
        self.assertEqual(response.status_code, 202, response.data)
        self.assertEqual(response.data['pos_sync_status'], PosSyncStatus.SYNCED)
        job = PosOutboxJob.objects.get(
            purchase_order=self.order, operation=PosOutboxOperation.REFRESH,
        )
        self.assertEqual(job.state, PosOutboxState.PENDING)

        fake = FakePosClient().script('read', read_back_body(
            self.po_no, [(code, '10.00', '4.00') for code, _ in self.sent_lines()],
            status='PARTIAL', expected='1500.00',
        ))
        self.run_worker(fake)
        snapshot = PosRequestSnapshot.objects.get(purchase_order=self.order)
        self.assertEqual(snapshot.pos_status, 'PARTIAL')
        self.assertEqual(snapshot.expected_amount, Decimal('1500.00'))
        self.assertFalse(snapshot.stale)
        order = PurchaseOrder.objects.get(pk=self.order.pk)
        self.assertEqual(order.pos_expected_amount, Decimal('1500.00'))

    def test_a_failed_refresh_keeps_the_last_snapshot_and_flags_it_stale(self):
        self.sync()
        self.post_sync()
        fake = FakePosClient().script('read',
                                      PosUnknownOutcome('store is down'))
        self.run_worker(fake)
        snapshot = PosRequestSnapshot.objects.get(purchase_order=self.order)
        self.assertEqual(snapshot.pos_status, 'WAITING')   # last known, kept
        self.assertTrue(snapshot.stale)
        job = PosOutboxJob.objects.get(
            purchase_order=self.order, operation=PosOutboxOperation.REFRESH,
        )
        self.assertEqual(job.state, PosOutboxState.PENDING)
        self.assertGreater(job.attempts, 0)

    def test_pos_sync_re_arms_a_failed_import(self):
        fake = FakePosClient().script(
            'import', PosRefused('TOKEN_TAKEN', 409, 'taken'),
        )
        self.run_worker(fake)
        self.assertEqual(
            PurchaseOrder.objects.get(pk=self.order.pk).pos_sync_status,
            PosSyncStatus.FAILED,
        )
        response = self.post_sync()
        self.assertEqual(response.status_code, 202, response.data)
        job = PosOutboxJob.objects.get(pk=self.import_job.pk)
        self.assertEqual(job.state, PosOutboxState.PENDING)
        self.assertEqual(job.attempts, 0)

    def test_pos_sync_on_a_never_sent_order_re_arms_the_pending_import(self):
        response = self.post_sync()
        self.assertEqual(response.status_code, 202, response.data)
        job = PosOutboxJob.objects.get(pk=self.import_job.pk)
        self.assertEqual(job.state, PosOutboxState.PENDING)
        self.assertIsNone(job.next_attempt_at)


class PosRouteAccessTests(PosWorkflowCase):
    def status_url(self, order=None):
        return f'/api/v1/purchase-orders/{(order or self.order).pk}/pos-status/'

    def test_pos_status_is_a_cached_read_that_writes_nothing(self):
        before = (PosOutboxJob.objects.count(), PosRequestSnapshot.objects.count())
        self.act_as(self.owner, Role.OWNER)
        response = self.client.get(self.status_url())
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['pos_sync_status'], PosSyncStatus.PENDING_SYNC)
        self.assertEqual(response.data['pos_status'], None)
        self.assertTrue(response.data['stale'])
        self.assertEqual(
            (PosOutboxJob.objects.count(), PosRequestSnapshot.objects.count()), before,
        )

    def test_the_snapshot_is_reported_with_its_raw_status_and_freshness(self):
        fake = FakePosClient().script(
            'import', import_body(self.po_no, self.sent_lines(), status='PARTIAL'),
        )
        self.run_worker(fake)
        self.act_as(self.owner, Role.OWNER)
        response = self.client.get(self.status_url())
        self.assertEqual(response.data['pos_status'], 'PARTIAL')
        self.assertEqual(response.data['pos_sync_status'], PosSyncStatus.SYNCED)
        self.assertFalse(response.data['stale'])
        self.assertIsNotNone(response.data['last_checked_at'])

    def test_an_old_read_back_is_reported_stale(self):
        fake = FakePosClient().script(
            'import', import_body(self.po_no, self.sent_lines()),
        )
        self.run_worker(fake)
        PosRequestSnapshot.objects.filter(purchase_order=self.order).update(
            last_checked_at=timezone.now() - timedelta(hours=2),
        )
        self.act_as(self.owner, Role.OWNER)
        self.assertTrue(self.client.get(self.status_url()).data['stale'])

    def test_owner_and_accountant_see_the_estimate_and_the_operations_roles_do_not(self):
        fake = FakePosClient().script(
            'import', import_body(self.po_no, self.sent_lines(), status='RELEASED'),
        )
        self.run_worker(fake)
        fake.script('read', read_back_body(
            self.po_no, [(code, '10.00', '2.00') for code, _ in self.sent_lines()],
            expected='2500.00',
        ))
        self.act_as(self.owner, Role.OWNER)
        self.client.post(f'/api/v1/purchase-orders/{self.order.pk}/pos-sync/')
        self.run_worker(fake)

        for user, role in (
            (self.owner, Role.OWNER),
            (self.accountant, Role.ACCOUNTANT),
            (self.admin, Role.ADMIN),
        ):
            with self.subTest(role=role):
                self.act_as(user, role)
                data = self.client.get(self.status_url()).data
                self.assertEqual(data['pos_expected_amount'], '2500.00')

        for user, role in ((self.engineer, Role.SITE_ENGINEER),):
            with self.subTest(role=role):
                self.act_as(user, role)
                data = self.client.get(self.status_url()).data
                self.assertNotIn('pos_expected_amount', data)

    def test_pos_status_returns_empty_lines_before_snapshot(self):
        self.act_as(self.owner, Role.OWNER)
        data = self.client.get(self.status_url()).data
        self.assertEqual(data['lines'], [])

    def test_pos_status_includes_matched_lines_without_money(self):
        fake = FakePosClient().script(
            'import', import_body(self.po_no, self.sent_lines(), status='ACCEPTED'),
        )
        self.run_worker(fake)
        fake.script('read', read_back_body(
            self.po_no, [('CEM-40KG', '10.00', '4.00')],
            status='PARTIAL', expected='2500.00',
        ))
        self.act_as(self.owner, Role.OWNER)
        self.client.post(f'/api/v1/purchase-orders/{self.order.pk}/pos-sync/')
        self.run_worker(fake)

        for user, role in ((self.owner, Role.OWNER), (self.engineer, Role.SITE_ENGINEER)):
            with self.subTest(role=role):
                self.act_as(user, role)
                data = self.client.get(self.status_url()).data
                self.assertEqual(data['lines'], [
                    {
                        'code': 'CEM-40KG',
                        'description': 'Portland Cement',
                        'unit': 'bag',
                        'requested': '10.00',
                        'released': '4.00',
                        'outstanding': '6.00',
                    },
                ])
                line_keys = set(data['lines'][0].keys())
                self.assertEqual(
                    line_keys,
                    {'code', 'description', 'unit', 'requested', 'released', 'outstanding'},
                )

    def test_pos_status_handles_unmatched_pos_code_without_crashing(self):
        PosRequestSnapshot.objects.create(
            purchase_order=self.order,
            pos_status='PARTIAL',
            lines=[
                {
                    'code': 'UNKNOWN-SKU',
                    'requested': '5.00',
                    'released': '2.00',
                    'outstanding': '3.00',
                },
            ],
            last_checked_at=timezone.now(),
            stale=False,
        )
        self.act_as(self.owner, Role.OWNER)
        data = self.client.get(self.status_url()).data
        self.assertEqual(data['lines'], [
            {
                'code': 'UNKNOWN-SKU',
                'description': '',
                'unit': '',
                'requested': '5.00',
                'released': '2.00',
                'outstanding': '3.00',
            },
        ])

    def test_order_rows_carry_the_store_status_for_their_chip(self):
        # Lists and the order header show where the store is; without this the
        # chip read "Sent to store" even after the cashier released everything.
        self.act_as(self.owner, Role.OWNER)
        listed = self.client.get('/api/v1/purchase-orders/').data
        self.assertIsNone(next(r for r in listed if r['id'] == self.order.pk)['store_status'])

        PosRequestSnapshot.objects.create(purchase_order=self.order, pos_status='RELEASED')
        listed = self.client.get('/api/v1/purchase-orders/').data
        detail = self.client.get(f'/api/v1/purchase-orders/{self.order.pk}/').data
        self.assertEqual(next(r for r in listed if r['id'] == self.order.pk)['store_status'], 'RELEASED')
        self.assertEqual(detail['order']['store_status'], 'RELEASED')

    def test_the_client_portal_has_no_pos_surface(self):
        self.act_as(self.client_user, Role.CLIENT)
        self.assertEqual(self.client.get(self.status_url()).status_code, 403)
        self.assertEqual(
            self.client.post(
                f'/api/v1/purchase-orders/{self.order.pk}/pos-sync/',
            ).status_code,
            403,
        )

    def test_an_out_of_scope_order_is_404_for_every_route(self):
        self.act_as(self.other_owner, Role.OWNER)
        self.assertEqual(self.client.get(self.status_url()).status_code, 404)
        self.assertEqual(
            self.client.post(
                f'/api/v1/purchase-orders/{self.order.pk}/pos-sync/',
            ).status_code,
            404,
        )

    def test_only_the_owner_enqueues_a_sync(self):
        for user, role in (
            (self.engineer, Role.SITE_ENGINEER),
            (self.accountant, Role.ACCOUNTANT),
            (self.admin, Role.ADMIN),
        ):
            with self.subTest(role=role):
                self.act_as(user, role)
                self.assertEqual(
                    self.client.post(
                        f'/api/v1/purchase-orders/{self.order.pk}/pos-sync/',
                    ).status_code,
                    403,
                )

    def test_an_external_order_has_no_pos_sync(self):
        material_request = self.make_request()
        self.act_as(self.owner, Role.OWNER)
        response = self.client.post(
            '/api/v1/purchase-orders/',
            {
                'request_id': material_request.pk,
                'category_id': self.category.pk,
                'source': 'external',
                'store_name': 'Downtown Hardware',
                'or_number': 'OR-778812',
                'lines': json.dumps([{
                    'material_id': self.cement.pk, 'description': 'Portland Cement',
                    'unit': 'bag', 'quantity': 5, 'unit_price': '260.00',
                }]),
                'receipt_photo': self._png(),
            },
            format='multipart',
        )
        self.assertEqual(response.status_code, 201, response.data)
        external = PurchaseOrder.objects.get(pk=response.data['id'])
        self.assertEqual(external.source, 'external')

        self.assertEqual(
            self.client.get(self.status_url(external)).data['pos_sync_status'],
            PosSyncStatus.NOT_APPLICABLE,
        )
        self.assertEqual(
            self.client.post(
                f'/api/v1/purchase-orders/{external.pk}/pos-sync/',
            ).status_code,
            400,
        )

    def test_no_route_or_log_leaks_the_bearer_or_the_operation_uuid(self):
        fake = FakePosClient().script(
            'import', import_body(self.po_no, self.sent_lines()),
        )
        self.run_worker(fake)
        self.act_as(self.owner, Role.OWNER)
        bodies = [
            self.client.get(self.status_url()).content.decode(),
            self.client.post(self.status_url().replace('pos-status', 'pos-sync')).content.decode(),
            self.client.get(
                f'/api/v1/purchase-orders/{self.order.pk}/',
            ).content.decode(),
        ]
        for body in bodies:
            self.assertNotIn(self.token, body)
            self.assertNotIn(str(self.order.pos_request_id), body)
            self.assertNotIn('Bearer', body)
            self.assertNotIn('jwt-', body)

    def _png(self):
        from .tests_procurement import png

        return png()


class WorkerClaimConcurrencyTests(ProcurementFixtures, TransactionTestCase):
    """Two workers run at once; the store must be asked exactly once."""

    client_class = APIClient

    # This class flushes the database; restore the serialized state afterwards.
    serialized_rollback = True

    def test_concurrent_workers_claim_each_job_once(self):
        _, response = self.place_order()
        order = PurchaseOrder.objects.get(pk=response.data['id'])
        job = order.outbox_jobs.get(operation=PosOutboxOperation.IMPORT)
        lines = [(line['code'], line['quantity']) for line in job.payload['items']]

        fake = FakePosClient()
        fake.script('import', import_body(order.po_no, lines))
        fake.script('import', import_body(order.po_no, lines))
        workers = []
        processed = []
        barrier = threading.Barrier(2)

        def worker():
            try:
                barrier.wait(timeout=10)
                processed.append(pos_worker.run_once(client=fake))
            finally:
                connections.close_all()

        workers = [threading.Thread(target=worker) for _ in range(2)]
        for thread in workers:
            thread.start()
        for thread in workers:
            thread.join(timeout=30)

        self.assertEqual(sorted(processed), [0, 1], processed)
        self.assertEqual(len(fake.imports), 1)
        self.assertEqual(sum(1 for name in fake.names() if name == 'import'), 1)


@override_settings(**POS_SETTINGS)
class AutoRefreshTests(PosWorkflowCase):
    """Automatic store status refresh for open synced own-store orders."""

    def _sync_order(self, order, status='WAITING'):
        job = order.outbox_jobs.get(operation=PosOutboxOperation.IMPORT)
        lines = [(line['code'], line['quantity']) for line in job.payload['items']]
        fake = FakePosClient().script('import', import_body(order.po_no, lines, status=status))
        self.run_worker(fake)

    def test_enqueue_auto_refresh_queues_open_synced_orders_only(self):
        # 1. Open synced order (`WAITING`) -> queued
        self._sync_order(self.order, status='WAITING')

        # 2. Open synced order (`PARTIAL`) -> queued
        _, resp_partial = self.place_order()
        partial_order = PurchaseOrder.objects.get(pk=resp_partial.data['id'])
        self._sync_order(partial_order, status='PARTIAL')

        # 3. Terminal synced orders (`RELEASED`, `DECLINED`, `CLOSED`) -> skipped
        terminal_orders = []
        for terminal_status in ('RELEASED', 'DECLINED', 'CLOSED'):
            _, resp = self.place_order()
            terminal = PurchaseOrder.objects.get(pk=resp.data['id'])
            self._sync_order(terminal, status=terminal_status)
            terminal_orders.append(terminal)

        # 4. Cancelled synced order -> skipped
        _, resp_cancelled = self.place_order()
        cancelled_order = PurchaseOrder.objects.get(pk=resp_cancelled.data['id'])
        self._sync_order(cancelled_order, status='ACCEPTED')
        self.act_as(self.owner, Role.OWNER)
        self.client.post(f'/api/v1/purchase-orders/{cancelled_order.pk}/cancel/')

        # 5. Unsynced (`PENDING_SYNC`) and `FAILED` orders -> skipped
        _, resp_pending = self.place_order()
        pending_order = PurchaseOrder.objects.get(pk=resp_pending.data['id'])
        _, resp_failed = self.place_order()
        failed_order = PurchaseOrder.objects.get(pk=resp_failed.data['id'])
        PurchaseOrder.objects.filter(pk=failed_order.pk).update(
            pos_sync_status=PosSyncStatus.FAILED,
        )

        # 6. External order -> skipped
        ext_req = self.make_request()
        from .tests_procurement import png
        ext_resp = self.client.post(
            '/api/v1/purchase-orders/',
            {
                'request_id': ext_req.pk,
                'category_id': self.category.pk,
                'source': 'external',
                'store_name': 'Downtown Hardware',
                'or_number': 'OR-101',
                'lines': json.dumps([{
                    'material_id': self.cement.pk,
                    'description': 'Portland Cement',
                    'unit': 'bag',
                    'quantity': 5,
                    'unit_price': '260.00',
                }]),
                'receipt_photo': png(),
            },
            format='multipart',
        )
        self.assertEqual(ext_resp.status_code, 201, ext_resp.data)
        external_order = PurchaseOrder.objects.get(pk=ext_resp.data['id'])

        queued = pos_worker.enqueue_auto_refresh()
        self.assertEqual(queued, 2)

        self.assertTrue(PosOutboxJob.objects.filter(
            purchase_order=self.order, operation=PosOutboxOperation.REFRESH,
            state=PosOutboxState.PENDING,
        ).exists())
        self.assertTrue(PosOutboxJob.objects.filter(
            purchase_order=partial_order, operation=PosOutboxOperation.REFRESH,
            state=PosOutboxState.PENDING,
        ).exists())
        for skipped in [*terminal_orders, pending_order, failed_order, cancelled_order, external_order]:
            self.assertFalse(PosOutboxJob.objects.filter(
                purchase_order=skipped, operation=PosOutboxOperation.REFRESH,
            ).exists())

    def test_enqueue_auto_refresh_reuses_refresh_job_without_duplicates(self):
        self._sync_order(self.order, status='WAITING')
        self.assertEqual(pos_worker.enqueue_auto_refresh(), 1)
        # Running again while PENDING skips and creates no duplicate row.
        self.assertEqual(pos_worker.enqueue_auto_refresh(), 0)
        self.assertEqual(PosOutboxJob.objects.filter(
            purchase_order=self.order, operation=PosOutboxOperation.REFRESH,
        ).count(), 1)

        # Backoff on a pending retry is preserved.
        job = PosOutboxJob.objects.get(
            purchase_order=self.order, operation=PosOutboxOperation.REFRESH,
        )
        future = timezone.now() + timedelta(minutes=5)
        PosOutboxJob.objects.filter(pk=job.pk).update(attempts=2, next_attempt_at=future)
        self.assertEqual(pos_worker.enqueue_auto_refresh(), 0)
        job.refresh_from_db()
        self.assertEqual(job.attempts, 2)
        self.assertEqual(job.next_attempt_at, future)

        # Process the refresh (store now reports ACCEPTED, still non-final).
        PosOutboxJob.objects.filter(pk=job.pk).update(next_attempt_at=None)
        fake = FakePosClient().script('read', read_back_body(
            self.po_no, [(code, '10.00', '0.00') for code, _ in self.sent_lines()],
            status='ACCEPTED',
        ))
        self.run_worker(fake)
        job.refresh_from_db()
        self.assertEqual(job.state, PosOutboxState.DONE)

        # Next auto-refresh re-arms the same row; manual pos-sync reuses it too.
        self.assertEqual(pos_worker.enqueue_auto_refresh(), 1)
        self.act_as(self.owner, Role.OWNER)
        self.assertEqual(
            self.client.post(f'/api/v1/purchase-orders/{self.order.pk}/pos-sync/').status_code,
            202,
        )
        self.assertEqual(PosOutboxJob.objects.filter(
            purchase_order=self.order, operation=PosOutboxOperation.REFRESH,
        ).count(), 1)

        # Once the store answers RELEASED, auto-refresh stops queuing.
        fake.script('read', read_back_body(
            self.po_no, [(code, '10.00', '10.00') for code, _ in self.sent_lines()],
            status='RELEASED',
        ))
        self.run_worker(fake)
        self.assertEqual(pos_worker.enqueue_auto_refresh(), 0)

    def test_run_pos_outbox_once_refreshes_open_synced_orders(self):
        self._sync_order(self.order, status='WAITING')
        fake = FakePosClient().script('read', read_back_body(
            self.po_no, [(code, '10.00', '10.00') for code, _ in self.sent_lines()],
            status='RELEASED',
        ))
        out = StringIO()
        with mock.patch('apps.requisitions.pos_worker.get_pos_client', return_value=fake):
            call_command('run_pos_outbox', '--once', stdout=out)
        self.assertIn('1 job(s) processed', out.getvalue())
        snapshot = PosRequestSnapshot.objects.get(purchase_order=self.order)
        self.assertEqual(snapshot.pos_status, 'RELEASED')

    @override_settings(POS_AUTO_REFRESH_SECONDS=15, POS_OUTBOX_POLL_SECONDS=30)
    def test_run_pos_outbox_loop_uses_pos_auto_refresh_seconds(self):
        self._sync_order(self.order, status='WAITING')
        fake = FakePosClient().script(
            'read',
            read_back_body(
                self.po_no, [(code, '10.00', '3.00') for code, _ in self.sent_lines()],
                status='PARTIAL',
            ),
            read_back_body(
                self.po_no, [(code, '10.00', '10.00') for code, _ in self.sent_lines()],
                status='RELEASED',
            ),
        )

        class StopLoop(BaseException):
            pass

        ticks = iter([100.0, 110.0, 116.0])
        sleeps = []

        def fake_sleep(seconds):
            sleeps.append(seconds)
            if len(sleeps) >= 3:
                raise StopLoop()

        with (
            mock.patch('apps.requisitions.pos_worker.get_pos_client', return_value=fake),
            mock.patch('apps.requisitions.management.commands.run_pos_outbox.time.monotonic', side_effect=ticks),
            mock.patch('apps.requisitions.management.commands.run_pos_outbox.time.sleep', side_effect=fake_sleep),
        ):
            with self.assertRaises(StopLoop):
                call_command('run_pos_outbox', stdout=StringIO())

        # Loop sleeps min(poll=30, auto_refresh=15) = 15s and executes both reads.
        self.assertEqual(sleeps, [15, 15, 15])
        self.assertEqual(fake.names(), ['read', 'read'])
        snapshot = PosRequestSnapshot.objects.get(purchase_order=self.order)
        self.assertEqual(snapshot.pos_status, 'RELEASED')
