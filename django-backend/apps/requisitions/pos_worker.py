"""Durable POS outbox worker (task 3.1b).

The worker is the only thing that calls the store, and it never invents an
identity: every job carries a stored payload, and an own-store order carries
`pos_token` minted once at placing. A retry re-sends **exactly** that payload
and token (`cpms_request_id = po.po_no`), because POS idempotency keys on the
pair and a regenerated token would be a second request.

Outcomes, from the contract's "Durable identity, retry and history":

* **Done** — the store confirmed this request and these lines; `pos_sync_status`
  becomes `synced`.
* **Retry** — a transient failure (unreachable, `5xx`, or an unknown outcome the
  store has no copy of yet). Attempts are counted, `next_attempt_at` is pushed
  back exponentially, and the order stays `pending_sync`.
* **Needs review (`failed`)** — a permanent refusal (`409 TOKEN_TAKEN`, any
  other `4xx`), a body naming another request or other lines, or an exhausted
  retry bound. Nothing retries it automatically; an owner may ask again through
  `POST purchase-orders/{id}/pos-sync/`.

An **unknown outcome is not a failure**: after a timeout, a disconnect, a `5xx`
or an unreadable 2xx body the worker reads `GET requests/{po_no}/` back. If the
store stored the request, the job is done (nothing is re-sent); if the store
answers `404` the exact same payload and token go out again.

Close jobs coordinate with the import: on a cancelled order an unsent import is
cancelled first, so a fresh live request can never appear at the store later.
While another worker is mid-import the close waits its turn instead of racing
it, and a close is never assumed to have reversed anything — its answer is the
store's own read-back.
"""

# Pyright runs without django-stubs, so model managers and FKs are untyped —
# the same documented false-positive class as `procurement_services.py`.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

import logging
from datetime import timedelta
from decimal import Decimal, InvalidOperation

from django.conf import settings
from django.db import DatabaseError, transaction
from django.db.models import Q
from django.utils import timezone

from ..projects import scoping
from ..projects.models import RoleOnProject
from ..projects.rules import NotAllowed, RuleRefused
from ..users.models import Role
from ..users.services import record
from . import rules
from .models import (
    MaterialSource,
    PosOutboxJob,
    PosOutboxOperation,
    PosOutboxState,
    PosRequestSnapshot,
    PosSyncStatus,
    PurchaseOrder,
    PurchaseOrderStatus,
)
from .pos_client import (
    PosError,
    PosNotFound,
    PosRefused,
    PosUnknownOutcome,
    get_pos_client,
)

logger = logging.getLogger(__name__)

#: Safety net for `run_once(limit=None)`: never loop forever in one process.
MAX_JOBS_PER_RUN = 200

#: How a line's quantity is read back, per route (import answers `quantity`,
#: read-back answers `requested`).
IMPORT_QUANTITY_KEYS = ('quantity',)
READ_BACK_QUANTITY_KEYS = ('requested',)


# --------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------

def _text(problem):
    """An exception as one line: no token, no traceback, no raw body."""
    message = str(problem or '').strip()
    return message or type(problem).__name__


def _decimal(value):
    """A finite Decimal from a wire string, or `None` (never zero-filled)."""
    if value is None or isinstance(value, bool):
        return None
    try:
        number = Decimal(str(value))
    except (InvalidOperation, ValueError):
        return None
    if not number.is_finite():
        return None
    return number


def _backoff_seconds(attempts):
    base = max(1, int(getattr(settings, 'POS_OUTBOX_BACKOFF_SECONDS', 30)))
    ceiling = max(base, int(getattr(settings, 'POS_OUTBOX_BACKOFF_MAX_SECONDS', 3600)))
    return min(base * (2 ** max(0, attempts - 1)), ceiling)


def _max_attempts():
    return max(1, int(getattr(settings, 'POS_OUTBOX_MAX_ATTEMPTS', 5)))


def _due(queryset, now):
    """Jobs whose turn has come; a `null` `next_attempt_at` means "now"."""
    return queryset.filter(state=PosOutboxState.PENDING).filter(
        Q(next_attempt_at__isnull=True) | Q(next_attempt_at__lte=now),
    )


# --------------------------------------------------------------------------
# Job bookkeeping
# --------------------------------------------------------------------------

def _order_of(job):
    return PurchaseOrder.objects.select_for_update().get(pk=job.purchase_order_id)


def _snapshot(order):
    snapshot, _ = PosRequestSnapshot.objects.get_or_create(purchase_order=order)
    return snapshot


def _store_snapshot(order, body, now):
    """Persist the store's own answer: raw status, budget estimate, lines."""
    snapshot = _snapshot(order)
    snapshot.pos_status = str(body.get('status') or '')[:32]
    snapshot.decline_reason = str(body.get('decline_reason') or '')
    snapshot.lines = [
        line for line in (body.get('items') or []) if isinstance(line, dict)
    ]
    snapshot.expected_amount = _amount(body.get('expected_amount'))
    snapshot.detail = ''
    snapshot.last_checked_at = now
    snapshot.stale = False
    snapshot.save()
    if (snapshot.expected_amount is not None
            and order.pos_expected_amount != snapshot.expected_amount):
        # A budget estimate for planning only — never invoice evidence.
        order.pos_expected_amount = snapshot.expected_amount
        order.save(update_fields=['pos_expected_amount', 'updated_at'])


def _amount(value):
    """`expected_amount` as a 2dp estimate, or `None` when it is not a number."""
    if value is None or isinstance(value, bool):
        return None
    try:
        number = Decimal(str(value))
    except (InvalidOperation, ValueError):
        return None
    if not number.is_finite() or number < 0 or number >= Decimal('1e12'):
        return None
    return number.quantize(Decimal('0.01'))


def _note(order, message):
    """Keep the last known snapshot, but say it may be out of date."""
    snapshot = _snapshot(order)
    snapshot.detail = message
    snapshot.stale = True
    snapshot.save(update_fields=['detail', 'stale', 'updated_at'])


def _done(job, message=''):
    job.state = PosOutboxState.DONE
    job.attempts += 1
    job.last_error = message
    job.next_attempt_at = None
    job.save(update_fields=[
        'state', 'attempts', 'last_error', 'next_attempt_at', 'updated_at',
    ])


def _drop(job, message):
    job.state = PosOutboxState.CANCELLED
    job.last_error = message
    job.next_attempt_at = None
    job.save(update_fields=['state', 'last_error', 'next_attempt_at', 'updated_at'])


def _failed(job, message, order=None):
    """Permanent: nothing retries it until a human looks (or an owner asks)."""
    job.state = PosOutboxState.FAILED
    job.attempts += 1
    job.last_error = message
    job.next_attempt_at = None
    job.save(update_fields=[
        'state', 'attempts', 'last_error', 'next_attempt_at', 'updated_at',
    ])
    if order is not None:
        if (job.operation == PosOutboxOperation.IMPORT
                and order.pos_sync_status == PosSyncStatus.PENDING_SYNC):
            order.pos_sync_status = PosSyncStatus.FAILED
            order.save(update_fields=['pos_sync_status', 'updated_at'])
        _note(order, message)


def _retry(job, message, now, order=None):
    if job.attempts + 1 >= _max_attempts():
        _failed(job, f'Gave up after {job.attempts + 1} attempts: {message}', order=order)
        return
    job.attempts += 1
    job.last_error = message
    job.next_attempt_at = now + timedelta(seconds=_backoff_seconds(job.attempts))
    job.save(update_fields=['attempts', 'last_error', 'next_attempt_at', 'updated_at'])


def _refusal(problem):
    return f'The store refused this order ({problem.code}): {problem.detail}'.strip()


def _lines_of(payload):
    return [
        (str(line.get('code') or ''), line.get('quantity'))
        for line in (payload or {}).get('items') or []
        if isinstance(line, dict)
    ]


def _identity_problem(body, *, expected_id, expected_lines, quantity_keys):
    """`''` when the body names exactly this request and these lines.

    The store answers a retry with its FIRST stored copy, so the body — not our
    payload — is the proof of what the store now holds. A mismatch is never
    "synced": it needs review.
    """
    if not isinstance(body, dict):
        return 'The store answered with a body we cannot read; this needs review.'
    if str(body.get('cpms_request_id') or '') != str(expected_id):
        return 'The store answered for another request; this needs review.'
    stored = {}
    for line in body.get('items') or []:
        if not isinstance(line, dict):
            return 'The store answered with a line we cannot read; this needs review.'
        code = str(line.get('code') or '')
        quantity = next(
            (line.get(key) for key in quantity_keys if line.get(key) is not None),
            None,
        )
        stored[code] = _decimal(quantity)
    wanted = {code: _decimal(quantity) for code, quantity in expected_lines}
    if set(stored) != set(wanted):
        return 'The store holds different lines than we sent; this needs review.'
    if any(stored[code] != wanted[code] for code in wanted):
        return 'The store holds different quantities than we sent; this needs review.'
    return ''


# --------------------------------------------------------------------------
# The three job kinds
# --------------------------------------------------------------------------

def _resolve_payer(order, job, payload, client):
    """Send the own-store supplier's CURRENT payer.

    The payer is store master data, not request identity: a payer corrected in
    the supplier list (or by `seed_demo --auto-pos-payer`) must heal an order
    whose stored payload still carries the refused one. With none set anywhere,
    the first payer POS lists (`customers/`) is adopted for the supplier.
    """
    project_block = payload.get('project')
    if not isinstance(project_block, dict):
        return
    supplier = order.supplier if order.supplier_id else None
    payer_id = supplier.pos_payer_id if supplier else None
    if payer_id is None:
        payer_id = project_block.get('payer')
    if payer_id is None and hasattr(client, 'list_customers'):
        try:
            for row in client.list_customers():
                if isinstance(row, dict) and row.get('id') is not None:
                    payer_id = int(row['id'])
                    break
        except Exception:
            payer_id = None
        if payer_id is not None and supplier:
            supplier.pos_payer_id = payer_id
            supplier.save(update_fields=['pos_payer_id', 'updated_at'])
    if payer_id is not None and payer_id != project_block.get('payer'):
        project_block = dict(project_block)
        project_block['payer'] = payer_id
        payload['project'] = project_block
        job.payload = dict(payload)
        job.save(update_fields=['payload', 'updated_at'])


def _run_import(job, client, now):
    order = _order_of(job)
    if order.status == PurchaseOrderStatus.CANCELLED:
        _drop(job, 'The order was cancelled before it reached the store.')
        return
    if not order.pos_token:
        _failed(job, 'This order has no stored POS token; it cannot be sent safely.',
                order=order)
        return

    payload = dict(job.payload or {})
    _resolve_payer(order, job, payload, client)
    # The token lives on the order (minted once, never serialized); it is added
    # here so a retry always carries the same one.
    payload['token'] = str(order.pos_token)
    try:
        body = client.import_request(
            payload, material_request=order.material_request_id,
        )
    except PosRefused as problem:
        _failed(job, _refusal(problem), order=order)
        return
    except PosUnknownOutcome as problem:
        _reconcile_import(job, order, client, payload, problem, now)
        return
    except PosError as problem:
        _retry(job, _text(problem), now, order=order)
        return

    problem = _identity_problem(
        body, expected_id=order.po_no, expected_lines=_lines_of(payload),
        quantity_keys=IMPORT_QUANTITY_KEYS,
    )
    if problem:
        _failed(job, problem, order=order)
        return
    order.pos_sync_status = PosSyncStatus.SYNCED
    order.save(update_fields=['pos_sync_status', 'updated_at'])
    _store_snapshot(order, body, now)
    _done(job)


def _reconcile_import(job, order, client, payload, problem, now):
    """After an unknown outcome: ask the store what it holds, then decide."""
    try:
        body = client.read_request(order.po_no)
    except PosNotFound:
        # The store never stored it: the same identity may be sent again.
        _retry(job, f'The store has no copy yet ({_text(problem)}).', now, order=order)
        return
    except PosError as error:
        _retry(job, f'The store outcome is unknown ({_text(error)}).', now, order=order)
        return

    mismatch = _identity_problem(
        body, expected_id=order.po_no, expected_lines=_lines_of(payload),
        quantity_keys=READ_BACK_QUANTITY_KEYS,
    )
    if mismatch:
        _failed(job, mismatch, order=order)
        return
    order.pos_sync_status = PosSyncStatus.SYNCED
    order.save(update_fields=['pos_sync_status', 'updated_at'])
    _store_snapshot(order, body, now)
    _done(job, 'Reconciled by reading the store back after an unknown outcome.')


def _run_close(job, client, now):
    order = _order_of(job)
    if _import_in_flight(order):
        _retry(job, 'The store import for this order is still running; the close waits.',
               now)
        return
    _cancel_unsent_import(order)
    if not order.po_no:
        _failed(job, 'This order has no order number to close at the store.',
                order=order)
        return

    try:
        body = client.close_request(order.po_no)
    except PosNotFound:
        # Nothing was ever stored there, so there is nothing to close.
        _note(order, 'The store has no copy of this order; there was nothing to close.')
        _done(job, 'The store had no copy of this order.')
        return
    except PosRefused as problem:
        if problem.code == 'REQUEST_CANCELLED':
            # The store already killed the remainder; a close cannot undo that.
            _note(order, 'The store had already cancelled this request.')
            _done(job, 'The store had already cancelled this request.')
            return
        _failed(job, _refusal(problem), order=order)
        return
    except PosUnknownOutcome as problem:
        _reconcile_close(job, order, client, problem, now)
        return
    except PosError as problem:
        _retry(job, _text(problem), now, order=order)
        return

    if str(body.get('cpms_request_id') or '') != str(order.po_no):
        _failed(job, 'The store answered a close for another request; this needs review.',
                order=order)
        return
    _store_snapshot(order, body, now)
    _done(job)


def _reconcile_close(job, order, client, problem, now):
    """A close that timed out: read the request back before trying again."""
    try:
        body = client.read_request(order.po_no)
    except PosNotFound:
        _note(order, 'The store has no copy of this order; there was nothing to close.')
        _done(job, 'The store had no copy of this order.')
        return
    except PosError as error:
        _retry(job, f'The close outcome is unknown ({_text(error)}).', now, order=order)
        return
    _store_snapshot(order, body, now)
    status = str(body.get('status') or '').upper()
    if status in ('CLOSED', 'RELEASED', 'DECLINED', 'CANCELLED'):
        # The store already holds the outcome a close would have produced.
        _done(job, f'The store reports {status}; the close landed.')
        return
    _retry(job, f'The store reports {status or "no status"} ({_text(problem)}).',
           now, order=order)


def _run_refresh(job, client, now):
    order = _order_of(job)
    try:
        body = client.read_request(order.po_no)
    except PosNotFound:
        _failed(job, 'The store has no copy of this order; this needs review.', order=order)
        return
    except PosRefused as problem:
        _failed(job, _refusal(problem), order=order)
        return
    except PosError as problem:
        _note(order, 'The store could not be read; this status may be out of date.')
        _retry(job, _text(problem), now)
        return
    _store_snapshot(order, body, now)
    _done(job)


def _import_in_flight(order):
    """Whether another worker is sending this order's import right now."""
    import_job = PosOutboxJob.objects.filter(
        purchase_order=order, operation=PosOutboxOperation.IMPORT,
    ).exclude(state__in=[PosOutboxState.DONE, PosOutboxState.CANCELLED]).first()
    if import_job is None:
        return False
    try:
        # `nowait`: the row is either free (nobody is sending it) or held by a
        # worker mid-call, in which case the close must wait for it.
        with transaction.atomic():
            PosOutboxJob.objects.select_for_update(nowait=True).get(pk=import_job.pk)
    except DatabaseError:
        return True
    return False


def _cancel_unsent_import(order):
    """A cancelled order must never import a fresh live request afterwards."""
    PosOutboxJob.objects.filter(
        purchase_order=order,
        operation=PosOutboxOperation.IMPORT,
        state=PosOutboxState.PENDING,
    ).update(
        state=PosOutboxState.CANCELLED,
        last_error='Cancelled because the order was cancelled.',
        next_attempt_at=None,
        updated_at=timezone.now(),
    )


# --------------------------------------------------------------------------
# Entry points
# --------------------------------------------------------------------------

def _process(job, client, now):
    if job.operation == PosOutboxOperation.IMPORT:
        _run_import(job, client, now)
    elif job.operation == PosOutboxOperation.CLOSE:
        _run_close(job, client, now)
    elif job.operation == PosOutboxOperation.REFRESH:
        _run_refresh(job, client, now)
    else:  # pragma: no cover - the enum is the whole set
        _failed(job, f'Unknown outbox operation {job.operation!r}.')


def claim_next(now=None):
    """The next due job locked for this worker; call inside `transaction.atomic`.

    `skip_locked` is what makes several workers safe: a job another worker is
    already holding is invisible here, so it is claimed exactly once.
    """
    now = now or timezone.now()
    return _due(
        PosOutboxJob.objects.select_for_update(skip_locked=True), now,
    ).order_by('id').first()


def run_once(client=None, limit=None, now=None):
    """Process every due job once. Returns how many jobs were handled."""
    client = client if client is not None else get_pos_client()
    now = now or timezone.now()
    processed = 0
    while limit is None or processed < limit:
        if processed >= MAX_JOBS_PER_RUN:
            logger.warning('POS outbox stopped at %s jobs in one run.', processed)
            break
        with transaction.atomic():
            job = claim_next(now)
            if job is None:
                break
            _process(job, client, now)
        processed += 1
    return processed


def request_sync(user, role, order, now=None):
    """`POST purchase-orders/{id}/pos-sync/` — the owner asks the worker again.

    A synced order gets a read-back refresh; an order the store has not accepted
    yet re-arms its stored import (same payload, same token). A cancelled order
    whose close gave up re-arms only that close. Nothing here calls the store:
    the worker does, so a slow or offline store never blocks a request.
    """
    now = now or timezone.now()
    if role != Role.OWNER:
        raise NotAllowed(rules.NOT_THE_PM)
    if not scoping.has_accepted_assignment(order.project, user, RoleOnProject.OWNER):
        raise NotAllowed(rules.NOT_THE_PM)
    if order.source != MaterialSource.OWN_STORE:
        raise RuleRefused('Only own-store orders are sent to the store.')
    if order.status == PurchaseOrderStatus.CANCELLED:
        job = _rearm_failed_close(order)
        record(
            user, 'pos_sync_requested', 'purchase_order', order.pk,
            {'operation': job.operation, 'pos_sync_status': order.pos_sync_status},
        )
        return _status_payload(order, role, now)

    with transaction.atomic():
        order = PurchaseOrder.objects.select_for_update().get(pk=order.pk)
        if order.pos_sync_status == PosSyncStatus.SYNCED:
            job = _refresh_job(order, user)
        elif order.pos_sync_status in (PosSyncStatus.PENDING_SYNC, PosSyncStatus.FAILED):
            job = _import_job(order)
        else:
            raise RuleRefused('This order was never queued for the store.')
        _rearm(job)
        if order.pos_sync_status == PosSyncStatus.FAILED:
            # The owner asked again: it is waiting on the store once more.
            order.pos_sync_status = PosSyncStatus.PENDING_SYNC
            order.save(update_fields=['pos_sync_status', 'updated_at'])
        record(
            user, 'pos_sync_requested', 'purchase_order', order.pk,
            {'operation': job.operation, 'pos_sync_status': order.pos_sync_status},
        )
    return _status_payload(order, role, now)


def _status_payload(order, role, now):
    from .procurement_serializers import pos_status_payload  # avoid an import cycle

    return pos_status_payload(order, role, now=now)


def _rearm_failed_close(order):
    """A cancelled order whose close gave up: the owner may retry **that** close.

    Nothing else is re-armed: the cancelled refusal stands unless a failed close
    job is actually there, and no import or new request is ever created.
    """
    with transaction.atomic():
        order = PurchaseOrder.objects.select_for_update().get(pk=order.pk)
        job = order.outbox_jobs.filter(
            operation=PosOutboxOperation.CLOSE, state=PosOutboxState.FAILED,
        ).first()
        if job is None:
            raise RuleRefused('This order was cancelled.')
        _rearm(job)
    return job


def _refresh_job(order, user):
    job, _ = PosOutboxJob.objects.get_or_create(
        idempotency_key=f'refresh:{order.pos_request_id}',
        defaults={
            'purchase_order': order,
            'operation': PosOutboxOperation.REFRESH,
            'payload': {'cpms_request_id': order.po_no},
            'created_by': user,
        },
    )
    return job


def _import_job(order):
    job = PosOutboxJob.objects.filter(
        purchase_order=order, operation=PosOutboxOperation.IMPORT,
    ).first()
    if job is None:
        # The payload is a snapshot of masters at placing time; rebuilding it
        # now would send a different request under the same identity.
        raise RuleRefused(
            'This order has no stored store payload, so it cannot be re-sent.',
        )
    return job


def _rearm(job):
    job.state = PosOutboxState.PENDING
    job.attempts = 0
    job.next_attempt_at = None
    job.save(update_fields=['state', 'attempts', 'next_attempt_at', 'updated_at'])
