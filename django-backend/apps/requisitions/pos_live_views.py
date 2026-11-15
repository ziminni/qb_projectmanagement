"""Live reads from the store: its catalogue (price, stock status) and the debt it holds.

The store owns the price of what it sells and the record of what a project owes it, so
CPMS never keeps its own copy: each request asks the store through the CPMS service
account (`PosClient`). Nothing is written here and nothing is cached, so a screen always
shows the store's current answer, or says plainly that the store could not be reached.

Failures never leak internals (hosts, ports, the store's own text): the caller gets a
generic message and the detail stays in the CPMS log and `PosSyncLog`.
"""

from django.utils import timezone
from rest_framework import status as http_status
from rest_framework.decorators import api_view
from rest_framework.response import Response

from ..master_data.models import MaterialItem
from ..projects import scoping
from ..projects.rules import NotAllowed
from ..users import capabilities
from ..users.models import Role
from .pos_client import PosConfigError, PosError, PosNotFound, _decimal, get_pos_client

OWNER_ONLY = 'Only the project manager reads the store catalogue.'
FINANCE_ONLY = 'Owner or Accountant role required to see what a project owes the store.'
STORE_UNREACHABLE = 'The store could not be reached. Try again in a moment.'
STORE_NOT_CONFIGURED = 'The store connection is not set up on this server.'
STORE_UNREADABLE = 'The store sent an answer CPMS could not read.'
STOCK_STATUSES = {'in_stock', 'low', 'out'}


def _store_down(problem):
    if isinstance(problem, PosConfigError):
        return Response(
            {'detail': STORE_NOT_CONFIGURED},
            status=http_status.HTTP_503_SERVICE_UNAVAILABLE,
        )
    return Response(
        {'detail': STORE_UNREACHABLE}, status=http_status.HTTP_502_BAD_GATEWAY,
    )


@api_view(['GET'])
def pos_catalog_view(request):
    """`pos-catalog/` — the store's selling units with its price and stock status.

    Each row is joined to the CPMS material that carries the same `pos_code`, so an
    order line can use the server's own material id. A store item no CPMS material
    points at has `material_id: null` and cannot be ordered until an admin maps it.
    """
    if capabilities.active_role(request) != Role.OWNER:
        raise NotAllowed(OWNER_ONLY)
    try:
        rows = get_pos_client().list_materials()
    except PosError as problem:
        return _store_down(problem)

    rows = [row for row in rows if isinstance(row, dict) and row.get('code')]
    ids = {}
    for code, pk in MaterialItem.objects.filter(
        pos_code__in=[str(row['code']) for row in rows],
    ).order_by('-pk').values_list('pos_code', 'pk'):
        ids[code] = pk  # ascending pk wins when two materials share a code
    result = []
    for row in rows:
        price = _decimal(row.get('price'))
        stock = row.get('stock_status')
        result.append({
            'code': str(row['code']),
            'product': str(row.get('product') or ''),
            'unit': str(row.get('unit') or ''),
            # Unknown is null, never zero: a price we cannot read must not look free.
            'price': None if price is None else str(price),
            'stock_status': stock if stock in STOCK_STATUSES else None,
            'material_id': ids.get(str(row['code'])),
        })
    return Response(result)


@api_view(['GET'])
def pos_payables_view(request, pk):
    """`projects/{id}/pos-payables/` — what this project owes the store, as the store says.

    The store holds the debt record (owner decision 2026-11-15); CPMS only reads it.
    The store knows the project by its CPMS `code`. A project the store has never been
    sent reads as nothing owed yet (`at_store: false`); an unreadable answer is a 502,
    never a fabricated zero.
    """
    role = capabilities.active_role(request)
    if role not in capabilities.FINANCE_ROLES:
        raise NotAllowed(FINANCE_ONLY)
    project = scoping.project_or_404(request.user, role, pk)
    try:
        body = get_pos_client().project_payables(project.code)
    except PosNotFound:
        return Response({
            'project_id': project.pk, 'at_store': False,
            'total': '0.00', 'paid': '0.00', 'balance': '0.00',
            'fetched_at': timezone.now().isoformat(),
        })
    except PosError as problem:
        return _store_down(problem)

    amounts = {
        key: _decimal(body.get(key)) if isinstance(body, dict) else None
        for key in ('total', 'paid', 'balance')
    }
    if any(value is None for value in amounts.values()):
        return Response(
            {'detail': STORE_UNREADABLE}, status=http_status.HTTP_502_BAD_GATEWAY,
        )
    return Response({
        'project_id': project.pk, 'at_store': True,
        **{key: str(value) for key, value in amounts.items()},
        'fetched_at': timezone.now().isoformat(),
    })
