"""HTTP client for the POS backend (Repo #1).

All cross-system calls funnel through here so that authentication, timeouts,
error handling and the audit trail (PosSyncLog) stay in one place.
"""

import logging
import time

import requests
from django.conf import settings

from .models import PosSyncLog

logger = logging.getLogger(__name__)


class PosAPIError(Exception):
    """Raised when the POS backend is unreachable or returns an error."""


class PosAPIClient:
    """Thin, synchronous REST client for the hardware-store POS API.

    The base URL defaults to POS_API_BASE_URL, which inside Docker resolves
    to the host via `host.docker.internal` (see docker-compose extra_hosts).
    """

    def __init__(self, base_url=None, token=None, timeout=None):
        self.base_url = (base_url or settings.POS_API_BASE_URL).rstrip('/')
        self.token = token if token is not None else settings.POS_API_TOKEN
        self.timeout = timeout or settings.POS_API_TIMEOUT

    # --- internals ---
    def _headers(self):
        headers = {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
        }
        if self.token:
            headers['Authorization'] = f'Bearer {self.token}'
        return headers

    def _record(self, *, method, endpoint, status_code, success,
                payload, response_payload, error, duration_ms,
                material_request=None, release_token=None):
        """Persist the call outcome. Logging must never break the request."""
        try:
            PosSyncLog.objects.create(
                material_request=material_request,
                release_token=release_token,
                endpoint=endpoint,
                method=method,
                status_code=status_code,
                success=success,
                request_payload=payload,
                response_payload=response_payload,
                error_message=error,
                duration_ms=duration_ms,
            )
        except Exception:  # pragma: no cover - audit must not mask the real error
            logger.exception('Failed to write PosSyncLog for %s %s', method, endpoint)

    def request(self, method, path, *, payload=None, material_request=None,
                release_token=None):
        """Perform a POS API call and return the decoded JSON body.

        Raises PosAPIError on transport failure or a non-2xx response.
        """
        endpoint = f'/{path.lstrip("/")}'
        url = f'{self.base_url}{endpoint}'
        started = time.monotonic()
        status_code = None
        response_payload = None
        error = ''
        success = False

        try:
            response = requests.request(
                method=method.upper(),
                url=url,
                json=payload,
                headers=self._headers(),
                timeout=self.timeout,
                verify=settings.POS_API_VERIFY_SSL,
            )
            status_code = response.status_code
            try:
                response_payload = response.json()
            except ValueError:
                # Non-JSON body (HTML error page, empty 204, ...)
                response_payload = {'raw': response.text[:2000]}

            success = response.ok
            if not success:
                error = f'POS API returned HTTP {response.status_code}'
        except requests.RequestException as exc:
            error = f'{type(exc).__name__}: {exc}'
            logger.warning('POS API call failed: %s %s — %s', method, url, error)
        finally:
            duration_ms = int((time.monotonic() - started) * 1000)
            self._record(
                method=method.upper(),
                endpoint=endpoint,
                status_code=status_code,
                success=success,
                payload=payload,
                response_payload=response_payload,
                error=error,
                duration_ms=duration_ms,
                material_request=material_request,
                release_token=release_token,
            )

        if not success:
            raise PosAPIError(error or 'POS API request failed')
        return response_payload

    # --- POS operations ---
    def health(self):
        """Check reachability of the POS backend."""
        return self.request('GET', '/api/health/')

    def push_requisition(self, material_request, items):
        """Notify the POS of an approved requisition.

        `items` is a list of {item_sku, quantity, unit, unit_cost} dicts.
        """
        payload = {
            'reference_no': material_request.request_no,
            'project_code': material_request.project.code,
            'site_code': material_request.site.code,
            'priority': material_request.priority,
            'needed_date': (
                material_request.needed_date.isoformat()
                if material_request.needed_date else None
            ),
            'items': items,
        }
        return self.request(
            'POST',
            '/api/v1/requisitions/',
            payload=payload,
            material_request=material_request,
        )

    def issue_release_token(self, release_token):
        """Register an issued release token with the POS so it can be redeemed."""
        material_request = release_token.material_request
        payload = {
            'token': release_token.token,
            'reference_no': material_request.request_no,
            'project_code': material_request.project.code,
            'site_code': material_request.site.code,
            'expires_at': release_token.expires_at.isoformat(),
            'items': [
                {
                    'item_sku': item.item_sku,
                    'quantity': str(item.quantity_approved),
                    'unit': item.unit,
                }
                for item in material_request.items.all()
            ],
        }
        return self.request(
            'POST',
            '/api/v1/requisitions/release-tokens/',
            payload=payload,
            material_request=material_request,
            release_token=release_token,
        )

    def sync_collectible(self, collectible):
        """Push an utang/collectible entry to the POS ledger."""
        payload = {
            'reference_no': collectible.reference_no,
            'debtor_name': collectible.debtor_name,
            'debtor_contact': collectible.debtor_contact,
            'amount': str(collectible.amount),
            'due_date': collectible.due_date.isoformat() if collectible.due_date else None,
            'project_code': collectible.project.code if collectible.project_id else None,
        }
        return self.request('POST', '/api/v1/collectibles/', payload=payload)


def get_pos_client(**kwargs):
    """Factory for the default configured POS client."""
    return PosAPIClient(**kwargs)


def issue_release_token_for(material_request, user=None, ttl_hours=None):
    """Issue a ReleaseToken locally and register it with the POS.

    The token is persisted first: if the POS call fails, the token still
    exists locally (ACTIVE) and can be re-pushed, and the failure is visible
    in PosSyncLog rather than lost.
    """
    from .models import ReleaseToken

    token = ReleaseToken.issue_for(material_request, user=user, ttl_hours=ttl_hours)
    try:
        get_pos_client().issue_release_token(token)
    except PosAPIError:
        logger.warning(
            'Release token %s issued locally but not registered with POS.',
            token.token,
        )
    return token