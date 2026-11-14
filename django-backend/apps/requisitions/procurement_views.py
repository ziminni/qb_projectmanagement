"""Phase 3 procurement views — scoped reads, role-checked writes.

Check order everywhere follows the Phase 2 convention:

1. authentication (global DRF default);
2. **scope** via `scoping.projects_for()` — out of scope is always `404`;
3. **role** on the resolved object — in scope but wrong role is `403`;
4. the business rule, which answers `400 {"detail": "<mock text>"}`.

The client role has no procurement surface at all (`403`), finance-only keys are
omitted by the serializers, and receipt evidence is served only through the
authenticated private download routes below — `MEDIA_URL` is never mounted.

Writes live in `procurement_services.py`; this file only picks querysets,
checks the role and renders.
"""

# Pyright runs without django-stubs/DRF stubs (untyped managers, actions).
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportGeneralTypeIssues=false

from django.http import FileResponse
from django.shortcuts import get_object_or_404
from rest_framework import status as http_status
from rest_framework.decorators import action, api_view
from rest_framework.exceptions import NotFound
from rest_framework.response import Response

from ..projects import scoping
from ..projects.models import Category
from ..projects.rules import NotAllowed, RuleRefused
from ..projects.views import ScopedViewSet
from ..site_reports import uploads as upload_rules
from ..users import capabilities
from . import procurement_services as services
from . import rules
from .inventory import site_inventory
from .models import (
    Delivery,
    MaterialRequest,
    MaterialRequestStatus,
    PurchaseOrder,
    PurchaseOrderStatus,
)
from .procurement_serializers import (
    DeliveryItemSerializer,
    DeliverySerializer,
    MaterialRequestItemSerializer,
    MaterialRequestSerializer,
    PurchaseOrderItemSerializer,
    PurchaseOrderSerializer,
    SiteCountSerializer,
)


def require_procurement(role):
    """The client portal never reaches internal procurement routes."""
    if role not in capabilities.STAFF_ROLES:
        raise NotAllowed(rules.CLIENT_NO_PROCUREMENT)


def numeric_ids(request, name):
    """`?project=1,2` as an id list; a junk entry is a `400`, never a 500."""
    raw = request.query_params.get(name)
    if not raw:
        return []
    ids = []
    for part in str(raw).split(','):
        part = part.strip()
        if not part:
            continue
        try:
            ids.append(int(part))
        except (TypeError, ValueError) as error:
            raise RuleRefused(f'The {name} filter must be a number.') from error
    return ids


def scoped_project(request, role, raw_id):
    project = scoping.projects_for(request.user, role).filter(pk=raw_id).first()
    if project is None:
        raise NotFound()
    return project


def _delivery_payload(delivery, request, role):
    return {
        'delivery': DeliverySerializer(
            delivery, context={'request': request, 'role': role},
        ).data,
        'items': DeliveryItemSerializer(delivery.items.all(), many=True).data,
    }


class MaterialRequestViewSet(ScopedViewSet):
    """`material-requests/` — list, detail, create and the owner's rejection."""

    serializer_class = MaterialRequestSerializer

    def get_queryset(self):
        return MaterialRequest.objects.filter(
            project__in=self.projects(),
        ).select_related('project', 'requested_by')

    def list(self, request):
        role = self.role()
        require_procurement(role)
        queryset = self.get_queryset()
        project_ids = numeric_ids(request, 'project')
        if project_ids:
            queryset = queryset.filter(project_id__in=project_ids)
        status_filter = request.query_params.get('status')
        if status_filter:
            if status_filter not in MaterialRequestStatus.values:
                raise RuleRefused('Choose a valid status.')
            queryset = queryset.filter(status=status_filter)
        return Response(
            MaterialRequestSerializer(
                queryset.order_by('-created_at', '-id'), many=True,
                context={'request': request, 'role': role},
            ).data
        )

    def retrieve(self, request, pk=None):
        role = self.role()
        require_procurement(role)
        material_request = self.get_object()
        context = {'request': request, 'role': role}
        return Response({
            'request': MaterialRequestSerializer(material_request, context=context).data,
            'items': MaterialRequestItemSerializer(
                material_request.items.all(), many=True,
            ).data,
            'counts': SiteCountSerializer(
                material_request.counts.all(), many=True,
            ).data,
        })

    def create(self, request):
        role = self.role()
        try:
            project_id = int(str(request.data.get('project_id')))
        except (TypeError, ValueError) as error:
            raise RuleRefused('Project not found.') from error
        project = scoped_project(request, role, project_id)
        material_request = services.create_request(
            request.user, role, project, request.data,
        )
        return Response(
            MaterialRequestSerializer(
                material_request, context={'request': request, 'role': role},
            ).data,
            status=http_status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=['post'])
    def reject(self, request, pk=None):
        material_request = services.reject_request(
            request.user, self.role(), self.get_object(), request.data,
        )
        return Response(
            MaterialRequestSerializer(
                material_request,
                context={'request': request, 'role': self.role()},
            ).data
        )


class PurchaseOrderViewSet(ScopedViewSet):
    """`purchase-orders/` — place, list, detail, cancel, confirm deliveries."""

    serializer_class = PurchaseOrderSerializer

    def get_queryset(self):
        return PurchaseOrder.objects.filter(
            project__in=self.projects(),
        ).select_related('project', 'material_request', 'supplier')

    def list(self, request):
        role = self.role()
        require_procurement(role)
        queryset = self.get_queryset()
        project_ids = numeric_ids(request, 'project')
        if project_ids:
            queryset = queryset.filter(project_id__in=project_ids)
        status_filter = request.query_params.get('status')
        if status_filter:
            if status_filter not in PurchaseOrderStatus.values:
                raise RuleRefused('Choose a valid status.')
            queryset = queryset.filter(status=status_filter)
        return Response(
            PurchaseOrderSerializer(
                queryset.order_by('-po_no', '-id'), many=True,
                context={'request': request, 'role': role},
            ).data
        )

    def retrieve(self, request, pk=None):
        role = self.role()
        require_procurement(role)
        order = self.get_object()
        context = {'request': request, 'role': role}
        return Response({
            'order': PurchaseOrderSerializer(order, context=context).data,
            'items': PurchaseOrderItemSerializer(
                order.items.select_related('material'), many=True,
                context=context,
            ).data,
            'deliveries': [
                _delivery_payload(delivery, request, role)
                for delivery in order.deliveries.all()
            ],
            # Payables/payments are blocked financially (phase-3 contract) and
            # are therefore not built yet: the key stays an empty list so the
            # Flutter detail parser keeps working.
            'payments': [],
            'request_id': order.material_request_id,
        })

    def create(self, request):
        role = self.role()
        require_procurement(role)
        try:
            request_id = int(str(request.data.get('request_id')))
        except (TypeError, ValueError) as error:
            raise RuleRefused('Request not found.') from error
        material_request = MaterialRequest.objects.filter(
            pk=request_id, project__in=self.projects(),
        ).select_related('project').first()
        if material_request is None:
            raise NotFound()
        order = services.place_order(
            request.user, role, material_request.project, request.data,
            upload=request.FILES.get('receipt_photo'),
        )
        return Response(
            PurchaseOrderSerializer(
                order, context={'request': request, 'role': role},
            ).data,
            status=http_status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=['post'])
    def cancel(self, request, pk=None):
        order = services.cancel_order(
            request.user, self.role(), self.get_object(),
        )
        return Response(
            PurchaseOrderSerializer(
                order, context={'request': request, 'role': self.role()},
            ).data
        )

    @action(detail=True, methods=['post'], url_path='deliveries')
    def deliveries(self, request, pk=None):
        order = self.get_object()
        delivery = services.confirm_delivery(
            request.user, self.role(), order, request.data,
            upload=request.FILES.get('receipt_photo'),
        )
        return Response(
            DeliverySerializer(
                delivery,
                context={'request': request, 'role': self.role()},
            ).data,
            status=http_status.HTTP_201_CREATED,
        )


class DeliveryViewSet(ScopedViewSet):
    """`deliveries/` — newest first, each with the order it belongs to."""

    serializer_class = DeliverySerializer

    def get_queryset(self):
        return Delivery.objects.filter(
            purchase_order__project__in=self.projects(),
        ).select_related('purchase_order')

    def list(self, request):
        role = self.role()
        require_procurement(role)
        queryset = self.get_queryset()
        project_ids = numeric_ids(request, 'project')
        if project_ids:
            queryset = queryset.filter(purchase_order__project_id__in=project_ids)
        rows = [
            {
                'delivery': _delivery_payload(delivery, request, role),
                'order': PurchaseOrderSerializer(
                    delivery.purchase_order,
                    context={'request': request, 'role': role},
                ).data,
            }
            for delivery in queryset.order_by('-received_at', '-id')
        ]
        return Response(rows)


# --------------------------------------------------------------------------
# Project-nested and category-nested reads
# --------------------------------------------------------------------------

@api_view(['GET'])
def project_site_inventory_view(request, pk):
    """`projects/{id}/site-inventory/` — derived stock, zero writes."""
    role = capabilities.active_role(request)
    require_procurement(role)
    project = scoping.project_or_404(request.user, role, pk)
    lines = site_inventory(project)
    return Response([
        {
            'material_id': line['material_id'],
            'name': line['name'],
            'unit': line['unit'],
            'received': str(line['received']),
            'damaged': str(line['damaged']),
            'used': str(line['used']),
        }
        for line in lines
    ])


@api_view(['GET'])
def category_budget_view(request, pk):
    """`categories/{id}/procurement-budget/?amount=` — advisory BudgetCheck."""
    role = capabilities.active_role(request)
    require_procurement(role)
    category = get_object_or_404(
        Category.objects.select_related('project'), pk=pk,
    )
    scoping.project_or_404(request.user, role, category.project_id)
    payload = services.budget_check(
        request.user, role, category, request.query_params.get('amount'),
    )
    return Response(payload)


# --------------------------------------------------------------------------
# Private receipt evidence
# --------------------------------------------------------------------------

def _download(record, file_name_param):
    """Stream the stored receipt, refusing a name mismatch before disk access."""
    if record.receipt_file_name != file_name_param:
        raise NotFound()
    extension = upload_rules.extension_of(record.receipt_file_name)
    try:
        handle = open(record.receipt_file.path, 'rb')  # noqa: SIM115 - closed by FileResponse
    except OSError as error:
        raise NotFound() from error
    response = FileResponse(
        handle,
        as_attachment=True,
        filename=record.receipt_file_name,
        content_type=upload_rules.content_type(extension),
    )
    response['X-Content-Type-Options'] = 'nosniff'
    response['Cache-Control'] = 'private, no-store'
    return response


def _require_finance(request):
    """Receipt evidence is finance-sensitive: owner/accountant only, else 404."""
    role = capabilities.active_role(request)
    require_procurement(role)
    if not capabilities.sees_finance(role):
        raise NotFound()
    return role


@api_view(['GET'])
def purchase_order_receipt_view(request, pk, file_name):
    """`purchase-orders/{id}/receipt/{name}` — scoped, finance roles only."""
    role = _require_finance(request)
    order = get_object_or_404(PurchaseOrder.objects.select_related('project'), pk=pk)
    scoping.project_or_404(request.user, role, order.project_id)
    return _download(order, file_name)


@api_view(['GET'])
def delivery_receipt_view(request, pk, file_name):
    """`deliveries/{id}/receipt/{name}` — scoped, finance roles only."""
    role = _require_finance(request)
    delivery = get_object_or_404(
        Delivery.objects.select_related('purchase_order'), pk=pk,
    )
    scoping.project_or_404(
        request.user, role, delivery.purchase_order.project_id,
    )
    return _download(delivery, file_name)
