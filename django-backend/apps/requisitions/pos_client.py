"""HTTP client for the POS `/api/v1/integration/cpms/*` boundary (task 3.1b).

This is the only place in CPMS that talks to the store, and it talks to exactly
six routes of the verified POS surface (contract "Actual POS surface"):

    GET  customers/                        payers a project may bill
    GET  materials/                        selling-unit codes we may order
    POST requests/                         import one order (idempotent)
    GET  requests/{po_no}/                 read-back (status, lines, budget)
    POST requests/{po_no}/close/           close an abandoned remainder
    GET  projects/{project_code}/payables/  project debt (client only, no route)

Rules this module owns, because they are transport concerns and not the
worker's business:

* **Fixed origin.** `POS_API_BASE_URL` is validated once (HTTPS, no
  credentials in the URL, plain http only for a local/LAN host when
  `POS_API_ALLOW_INSECURE_LOCAL` is explicitly set). Callers pass an *id*, never
  a URL, and a `next` pagination link outside the configured origin is refused.
* **No redirects.** A `3xx` is an unknown outcome, not a place to send the
  bearer token.
* **In-memory service JWT.** `POS_API_SERVICE_USERNAME` / `_PASSWORD` are
  exchanged at `/api/v1/auth/login/`, refreshed once on a `401` via
  `/api/v1/auth/refresh/`, and never written to disk, logged, or returned.
* **Nothing secret is recorded.** `PosSyncLog` rows carry the redacted payload,
  and error text is scrubbed of any `Bearer <token>`.

Errors are deliberately three kinds, because the worker treats them
differently (contract "Durable identity, retry and history"):

* `PosRefused` / `PosNotFound` — the store answered; `4xx` is permanent.
* `PosUnknownOutcome` — timeout, disconnect, `5xx`, redirect or an unreadable
  body: the write may have applied, so the worker must reconcile, not retry.
* `PosAuthError` / `PosConfigError` — our side is wrong; nothing was attempted
  against the business routes.
"""

import ipaddress
import logging
import re
import time
from decimal import Decimal, InvalidOperation
from urllib.parse import urlsplit

import requests
from django.conf import settings

from .models import PosSyncLog

logger = logging.getLogger(__name__)

INTEGRATION_PREFIX = '/api/v1/integration/cpms'
LOGIN_PATH = '/api/v1/auth/login/'
REFRESH_PATH = '/api/v1/auth/refresh/'
REDACTED = '***'

#: Keys whose value never reaches a log, an error message or a stored payload.
SECRET_KEYS = frozenset({
    'token', 'pos_token', 'authorization', 'password', 'access', 'refresh', 'secret',
})

#: Hosts that are this machine or the LAN, where plain http is a dev choice.
LOCAL_HOSTS = frozenset({'localhost', 'host.docker.internal'})

#: A safe page cap for the two paginated catalogue reads.
MAX_PAGES = 100


class PosError(Exception):
    """Base class for everything this client raises."""


class PosConfigError(PosError):
    """The configured origin, credentials or request id is unusable."""


class PosTransportError(PosError):
    """The store could not be reached."""


class PosUnknownOutcome(PosTransportError):
    """Timeout, disconnect, 5xx or an unreadable 2xx body: the write MAY apply."""


class PosAuthError(PosError):
    """The service account could not authenticate, even after one refresh."""


class PosRefused(PosError):
    """A `4xx` refusal from the store, carrying its own `code`."""

    def __init__(self, code='POS_REFUSED', status_code=400, detail=''):
        super().__init__(detail or code)
        self.code = code
        self.status_code = status_code
        self.detail = detail


class PosNotFound(PosError):
    """`404` — the store holds no such request or project."""

    def __init__(self, code='NOT_FOUND', status_code=404, detail=''):
        super().__init__(detail or code)
        self.code = code
        self.status_code = status_code
        self.detail = detail


# --------------------------------------------------------------------------
# Redaction and origin validation
# --------------------------------------------------------------------------

def redact_payload(value):
    """A copy of `value` with every known secret replaced by `***`.

    Used for `PosSyncLog`, which outlives the job that wrote it. The input is
    never mutated: the caller keeps the real payload for the wire.
    """
    if isinstance(value, dict):
        return {
            key: (REDACTED if str(key).lower() in SECRET_KEYS else redact_payload(item))
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [redact_payload(item) for item in value]
    return value


def _clean(message):
    """Error text with anything token-shaped removed (defence in depth)."""
    return re.sub(r'Bearer\s+\S+', 'Bearer ***', str(message or ''))


def _is_local_host(host):
    """Whether `host` is this machine, the docker host or a private LAN address."""
    name = str(host or '').strip().strip('[]').lower()
    if not name:
        return False
    if name in LOCAL_HOSTS:
        return True
    try:
        address = ipaddress.ip_address(name)
    except ValueError:
        return name.endswith(('.local', '.internal'))
    return address.is_loopback or address.is_private


def validate_base_url(raw):
    """The configured POS origin, or `PosConfigError`.

    Only the scheme/host/optional path prefix is used; a query, a fragment or
    embedded credentials make the URL unusable (a secret must never travel in
    a URL we log).
    """
    text = str(raw or '').strip()
    parts = urlsplit(text)
    if parts.scheme not in ('http', 'https') or not parts.hostname:
        raise PosConfigError(
            'POS_API_BASE_URL must be an absolute http(s) URL, e.g. https://store.example.com',
        )
    if parts.username or parts.password:
        raise PosConfigError('POS_API_BASE_URL must not carry credentials.')
    if parts.query or parts.fragment:
        raise PosConfigError('POS_API_BASE_URL must not carry a query or a fragment.')
    if parts.scheme == 'http':
        if not getattr(settings, 'POS_API_ALLOW_INSECURE_LOCAL', False):
            raise PosConfigError(
                'POS_API_BASE_URL must use https:// (set POS_API_ALLOW_INSECURE_LOCAL '
                'only for a local/LAN development store).',
            )
        if not _is_local_host(parts.hostname):
            raise PosConfigError(
                'Plain http is only allowed for a local/LAN host; use https:// for '
                'a public store origin.',
            )
    return text.rstrip('/')


def _segment(value):
    """One path segment from a caller-supplied id — never a URL.

    `requests/{id}/` is the only shape the contract has, so anything that could
    change the path (a slash, a space, `..`, an over-long value) is refused
    before a socket is opened.
    """
    text = str(value or '').strip()
    if not text or len(text) > 100 or text in ('.', '..'):
        raise PosConfigError('A POS request id must be 1–100 characters.')
    if not all(character.isalnum() or character in '._-' for character in text):
        raise PosConfigError(
            'A POS request id may only contain letters, digits, dot, dash or underscore.',
        )
    return text


def _decimal(value):
    """A finite 2dp Decimal from a wire string, or `None`.

    The store sends money and quantities as strings; anything that is not a
    finite number is "unknown", never zero (contract: null means unknown).
    """
    if value is None or isinstance(value, bool):
        return None
    try:
        number = Decimal(str(value))
    except (InvalidOperation, ValueError):
        return None
    if not number.is_finite() or abs(number) >= Decimal('1e12'):
        return None
    return number.quantize(Decimal('0.01'))


class PosClient:
    """One configured connection to the store's CPMS boundary.

    Holds the service JWT in memory only: a new client logs in again, so a
    crashed worker cannot leave a token behind anywhere.
    """

    def __init__(self, base_url=None, timeout=None, username=None, password=None,
                 session=None):
        self.base_url = validate_base_url(
            base_url if base_url is not None else settings.POS_API_BASE_URL,
        )
        self.timeout = timeout or settings.POS_API_TIMEOUT
        self.username = (
            username if username is not None else settings.POS_API_SERVICE_USERNAME
        )
        self.password = (
            password if password is not None else settings.POS_API_SERVICE_PASSWORD
        )
        self.session = session if session is not None else requests.Session()
        self._access = None
        self._refresh_token = None

    # --- internals ------------------------------------------------------
    def _headers(self, *, has_body):
        headers = {'Accept': 'application/json'}
        if has_body:
            headers['Content-Type'] = 'application/json'
        if self._access:
            headers['Authorization'] = f'Bearer {self._access}'
        name = getattr(settings, 'POS_API_GATEWAY_HEADER_NAME', '')
        value = getattr(settings, 'POS_API_GATEWAY_HEADER_VALUE', '')
        if name and value:
            headers[name] = value
        return headers

    def _send(self, method, path, payload=None):
        url = f'{self.base_url}{path}'
        verify = getattr(settings, 'POS_API_VERIFY_SSL', True)
        try:
            return self.session.request(
                method=method,
                url=url,
                json=payload,
                headers=self._headers(has_body=payload is not None),
                timeout=self.timeout,
                verify=verify,
                # Never follow a redirect: it would hand the bearer token to
                # whatever origin the answer names.
                allow_redirects=False,
            )
        except requests.RequestException as error:
            raise PosUnknownOutcome(
                f'The store could not be reached ({type(error).__name__}).',
            ) from None

    @staticmethod
    def _json(response):
        try:
            return response.json()
        except ValueError:
            return None

    def _store_tokens(self, body):
        access = (body or {}).get('access')
        if not access:
            raise PosAuthError('The store answered a sign-in without an access token.')
        self._access = access
        if (body or {}).get('refresh'):
            self._refresh_token = body['refresh']

    def _login(self):
        if not self.username or not self.password:
            raise PosConfigError(
                'POS_API_SERVICE_USERNAME and POS_API_SERVICE_PASSWORD are required.',
            )
        response = self._send(
            'POST', LOGIN_PATH,
            {'identifier': self.username, 'password': self.password},
        )
        if not 200 <= response.status_code < 300:
            raise PosAuthError(
                f'The store refused the CPMS service account (HTTP {response.status_code}).',
            )
        self._store_tokens(self._json(response))

    def _refresh_access(self):
        if not self._refresh_token:
            self._login()
            return
        response = self._send(
            'POST', REFRESH_PATH, {'refresh': self._refresh_token},
        )
        if not 200 <= response.status_code < 300:
            self._access = None
            self._refresh_token = None
            self._login()
            return
        self._store_tokens(self._json(response))

    def _result(self, status, body):
        """The decoded body of a usable answer, or the matching error."""
        if 200 <= status < 300:
            if not isinstance(body, dict):
                raise PosUnknownOutcome(
                    f'The store answered HTTP {status} with a body we cannot read.',
                )
            return body
        if 300 <= status < 400:
            raise PosUnknownOutcome('The store answered with a redirect, which is never followed.')
        code = str((body or {}).get('code') or '')
        detail = str((body or {}).get('detail') or '')
        if status == 404:
            raise PosNotFound(code or 'NOT_FOUND', 404, detail)
        if 400 <= status < 500:
            raise PosRefused(code or f'HTTP_{status}', status, detail)
        # 5xx: the store may or may not have applied the call.
        raise PosUnknownOutcome(f'The store answered HTTP {status}.')

    def _record(self, *, method, path, status_code, payload, response_body,
                error, duration_ms, material_request=None):
        """Persist the call with its secrets removed. Never breaks the call."""
        try:
            PosSyncLog.objects.create(
                material_request_id=material_request,
                endpoint=path,
                method=method,
                status_code=status_code,
                success=not error and status_code is not None and 200 <= status_code < 300,
                request_payload=redact_payload(payload),
                response_payload=redact_payload(response_body),
                error_message=_clean(error),
                duration_ms=max(0, duration_ms),
            )
        except Exception:  # pragma: no cover - the trail must never mask the call
            logger.exception('Could not write the PosSyncLog row for %s %s.', method, path)

    def _call(self, method, path, payload=None, *, material_request=None):
        started = time.monotonic()
        status_code = None
        response_body = None
        error = ''
        try:
            if not self._access:
                self._login()
            response = self._send(method, path, payload)
            if response.status_code == 401:
                # The access token expired: refresh once, then give up.
                self._access = None
                self._refresh_access()
                response = self._send(method, path, payload)
                if response.status_code == 401:
                    raise PosAuthError(
                        'The store refused the CPMS service account even after a refresh.',
                    )
            status_code = response.status_code
            response_body = self._json(response)
            logger.debug('POS %s %s → %s', method, path, status_code)
            return self._result(status_code, response_body)
        except PosError as problem:
            error = _clean(problem)
            logger.warning('POS %s %s failed: %s', method, path, error)
            raise
        finally:
            self._record(
                method=method, path=path, status_code=status_code,
                payload=payload, response_body=response_body, error=error,
                duration_ms=int((time.monotonic() - started) * 1000),
                material_request=material_request,
            )

    def _pages(self, path):
        """Every row of a paginated list, following only same-origin pages."""
        rows = []
        current = path
        for _ in range(MAX_PAGES):
            body = self._call('GET', current)
            rows.extend(body.get('results') or [])
            following = body.get('next')
            if not following:
                return rows
            following = str(following)
            if not following.startswith(f'{self.base_url}/'):
                raise PosConfigError(
                    'The store answered a pagination link outside the configured origin.',
                )
            current = following[len(self.base_url):]
        raise PosUnknownOutcome('The store catalogue did not finish paging.')

    # --- the six routes -------------------------------------------------
    def import_request(self, payload, material_request=None):
        """`POST requests/` — 201 new, 200 the first stored copy on a retry."""
        return self._call(
            'POST', f'{INTEGRATION_PREFIX}/requests/', payload,
            material_request=material_request,
        )

    def read_request(self, cpms_request_id):
        """`GET requests/{cpms_request_id}/` — status, lines, live budget."""
        return self._call(
            'GET', f'{INTEGRATION_PREFIX}/requests/{_segment(cpms_request_id)}/',
        )

    def close_request(self, cpms_request_id):
        """`POST requests/{cpms_request_id}/close/` — abandon the remainder."""
        return self._call(
            'POST',
            f'{INTEGRATION_PREFIX}/requests/{_segment(cpms_request_id)}/close/',
            {},
        )

    def list_customers(self):
        """`GET customers/` — the payers a project may bill."""
        return self._pages(f'{INTEGRATION_PREFIX}/customers/')

    def list_materials(self):
        """`GET materials/` — `{code, product, unit, price, stock_status}` selling units."""
        return self._pages(f'{INTEGRATION_PREFIX}/materials/')

    def project_payables(self, cpms_project_id):
        """`GET projects/{cpms_project_id}/payables/` — what the project owes the store.

        The store holds the debt record (owner decision 2026-11-15); CPMS reads it
        through `pos_live_views.pos_payables_view`, never keeps its own copy.
        """
        return self._call(
            'GET',
            f'{INTEGRATION_PREFIX}/projects/{_segment(cpms_project_id)}/payables/',
        )


def get_pos_client():
    """A client configured from settings (the worker's default seam)."""
    return PosClient()
