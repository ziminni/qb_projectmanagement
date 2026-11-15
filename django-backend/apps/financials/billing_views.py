"""Billing views: progress billings, client payments, VOs and retention.

Check order follows the Phase 2/3/4 convention:

1. authentication (global DRF default);
2. the **active role** — `capabilities.active_role()`, never a union of held
   roles; the wrong active role is `403`;
3. **scope** via `scoping.project_or_404()` / `projects_for()` — an out-of-scope
   project is always `404`;
4. the business rule, which answers `400 {"detail": "<text>"}`.

The client portal is not a second API: it is the same routes with the active
role `client`, restricted to its own accepted projects and to billings already
sent (`billed` statuses). Draft and withdrawn billings are `404` for a client —
it may not learn that an unissued bill exists.
"""

# Pyright runs without django-stubs/DRF stubs (untyped managers, actions).
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportGeneralTypeIssues=false

from django.utils import timezone
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView

from ..projects import scoping
from ..projects.models import RoleOnProject
from ..projects.rules import NotAllowed, RuleRefused
from ..users import capabilities
from ..users.models import Role
from . import billing_math, billing_services
from . import billing_rules as rules
from . import billing_serializers as wire
from .models import BILLED_STATUSES, RetentionRelease


def first_error(errors):
    """The first DRF error text, walked through nested list/entry dicts."""
    for value in errors.values():
        if isinstance(value, dict):
            return first_error(value)
        if isinstance(value, list) and value:
            first = value[0]
            if isinstance(first, dict):
                return first_error(first)
            return str(first)
        return str(value)
    return 'This change was refused.'


def refused(serializer):
    return Response({'detail': first_error(serializer.errors)},
                    status=status.HTTP_400_BAD_REQUEST)


def project_id_from(data, key='project_id'):
    """A body/query `project_id` as an int; junk and booleans are a `400`."""
    raw = data.get(key)
    if isinstance(raw, bool) or raw in (None, ''):
        raise RuleRefused(rules.PROJECT_NOT_FOUND)
    if isinstance(raw, int):
        return raw
    try:
        return int(str(raw).strip())
    except (TypeError, ValueError) as error:
        raise RuleRefused(rules.PROJECT_NOT_FOUND) from error


def require_finance(role):
    """Owner or accountant only: the admin role has no billing surface."""
    if not capabilities.sees_finance(role):
        raise NotAllowed(rules.FINANCE_ONLY)


class ProgressBillingViewSet(viewsets.GenericViewSet,
                              mixins.ListModelMixin,
                              mixins.RetrieveModelMixin):
    """`progress-billings/` — finance reads and the client portal's view."""

    http_method_names = ('get', 'post', 'head', 'options')

    def role(self):
        return capabilities.active_role(self.request)

    def get_serializer_class(self):
        if self.action == 'retrieve':
            return wire.ProgressBillingDetailSerializer
        return wire.ProgressBillingSerializer

    def get_queryset(self):
        role = self.role()
        if role == Role.CLIENT:
            queryset = billing_services.billings_for(
                scoping.projects_for(self.request.user, role),
            )
            return queryset.filter(status__in=BILLED_STATUSES)
        require_finance(role)
        return billing_services.billings_for(
            scoping.projects_for(self.request.user, role),
        )

    def list(self, request, *args, **kwargs):
        queryset = self.get_queryset()
        raw_project = request.query_params.get('project')
        if raw_project:
            queryset = queryset.filter(project_id=project_id_from(
                request.query_params, 'project',
            ))
        raw_status = request.query_params.get('status')
        if raw_status:
            queryset = queryset.filter(status=raw_status)
        page = self.paginate_queryset(queryset)
        serializer = self.get_serializer(page, many=True)
        return self.get_paginated_response(serializer.data)

    # -- finance-only moves ---------------------------------------------------

    def owner_project(self):
        """`project_or_404` plus the accepted owner assignment the mock requires."""
        role = self.role()
        require_finance(role)
        project = scoping.project_or_404(
            self.request.user, role, project_id_from(self.request.data),
        )
        if not scoping.has_accepted_assignment(
            project, self.request.user, RoleOnProject.OWNER,
        ):
            raise NotAllowed(rules.OWNER_PREPARES)
        return project

    def finance_billing(self):
        require_finance(self.role())
        return self.get_object()

    def create(self, request, *args, **kwargs):
        project = self.owner_project()
        serializer = wire.CreateBillingSerializer(data=request.data)
        if not serializer.is_valid():
            return refused(serializer)
        billing = billing_services.create_billing(
            request.user, project, serializer.validated_data['period_end'],
        )
        return Response(
            wire.ProgressBillingSerializer(billing).data,
            status=status.HTTP_201_CREATED,
        )

    @action(detail=False, methods=['get'])
    def preview(self, request):
        require_finance(self.role())
        project = scoping.project_or_404(
            request.user, self.role(), project_id_from(request.query_params, 'project'),
        )
        serializer = wire.CreateBillingSerializer(data={
            'project_id': project.pk,
            'period_end': request.query_params.get('period_end'),
        })
        if not serializer.is_valid():
            return refused(serializer)
        figures = billing_math.preview(project, serializer.validated_data['period_end'])
        return Response(wire.BillingFiguresSerializer(figures).data)

    @action(detail=True, methods=['post'])
    def submit(self, request, pk=None):
        billing = billing_services.submit_billing(
            request.user, self.owner_billing(),
        )
        return Response(wire.ProgressBillingSerializer(billing).data)

    @action(detail=True, methods=['post'])
    def withdraw(self, request, pk=None):
        billing = billing_services.withdraw_billing(
            request.user, self.owner_billing(),
        )
        return Response(wire.ProgressBillingSerializer(billing).data)

    def owner_billing(self):
        """The billing of a project where the caller is an accepted owner."""
        billing = self.finance_billing()
        if not scoping.has_accepted_assignment(
            billing.project, self.request.user, RoleOnProject.OWNER,
        ):
            raise NotAllowed(rules.OWNER_PREPARES)
        return billing

    # -- client moves ---------------------------------------------------------

    def client_billing(self):
        if self.role() != Role.CLIENT:
            raise NotAllowed(rules.CLIENT_ONLY)
        # `get_queryset()` is client-scoped and billed-only: a draft is a 404.
        return self.get_object()

    @action(detail=True, methods=['post'], url_path='client-approve')
    def client_approve(self, request, pk=None):
        billing = billing_services.client_approve_billing(
            request.user, self.client_billing(),
        )
        return Response(wire.ProgressBillingSerializer(billing).data)

    @action(detail=True, methods=['post'], url_path='client-dispute')
    def client_dispute(self, request, pk=None):
        billing = self.client_billing()
        serializer = wire.ReasonSerializer(data=request.data)
        if not serializer.is_valid():
            return refused(serializer)
        billing = billing_services.client_dispute_billing(
            request.user, billing, serializer.validated_data['reason'],
        )
        return Response(wire.ProgressBillingSerializer(billing).data)

    # -- money ----------------------------------------------------------------

    @action(detail=True, methods=['post'])
    def payments(self, request, pk=None):
        billing = self.finance_billing()
        serializer = wire.RecordPaymentSerializer(data=request.data)
        if not serializer.is_valid():
            return refused(serializer)
        payment = billing_services.record_payment(
            request.user, billing,
            amount=serializer.validated_data['amount'],
            paid_on=serializer.validated_data.get('paid_on') or timezone.localdate(),
            method=serializer.validated_data['method'],
            reference_no=serializer.validated_data.get('reference_no', ''),
        )
        return Response(
            wire.ClientPaymentSerializer(payment).data,
            status=status.HTTP_201_CREATED,
        )


class ClientPaymentViewSet(viewsets.GenericViewSet, mixins.ListModelMixin):
    """`client-payments/` — owner/accountant only, like `billing-summary`.

    The client sees the payments of its own billing inside the billing detail;
    the portal's only payments caller (`ProjectFinancialsPage`) is finance-only.
    """

    serializer_class = wire.ClientPaymentSerializer
    http_method_names = ('get', 'head', 'options')

    def get_queryset(self):
        role = capabilities.active_role(self.request)
        require_finance(role)
        queryset = billing_services.payments_for(
            scoping.projects_for(self.request.user, role),
        )
        raw_project = self.request.query_params.get('project')
        if raw_project:
            queryset = queryset.filter(
                progress_billing__project_id=project_id_from(
                    self.request.query_params, 'project',
                ),
            )
        return queryset


class BillingSummaryView(APIView):
    """`billing-summary/` — `{billed, collected}` for the caller's projects."""

    def get(self, request):
        role = capabilities.active_role(request)
        require_finance(role)
        raw_project = request.query_params.get('project')
        if raw_project:
            # `?project=` narrows the caller's scope, never widens it.
            project = scoping.project_or_404(
                request.user, role,
                project_id_from(request.query_params, 'project'),
            )
            ids = [project.pk]
        else:
            ids = list(
                scoping.projects_for(request.user, role)
                .values_list('pk', flat=True),
            )
        return Response(billing_services.billing_summary(ids))


class VariationOrderViewSet(viewsets.GenericViewSet,
                            mixins.ListModelMixin,
                            mixins.RetrieveModelMixin):
    """`variation-orders/` — owner/site-engineer proposals, client answers."""

    http_method_names = ('get', 'post', 'patch', 'head', 'options')

    def role(self):
        return capabilities.active_role(self.request)

    def get_serializer_class(self):
        if self.action == 'retrieve':
            return wire.VariationOrderDetailSerializer
        return wire.VariationOrderSerializer

    def get_queryset(self):
        role = self.role()
        if role == Role.CLIENT:
            queryset = billing_services.vo_for(
                scoping.projects_for(self.request.user, role),
            )
            return queryset.filter(approved_by_owner__isnull=False)
        if role in (Role.OWNER, Role.SITE_ENGINEER):
            return billing_services.vo_for(
                scoping.projects_for(self.request.user, role),
            )
        raise NotAllowed(rules.VO_SURFACE)

    def list(self, request, *args, **kwargs):
        queryset = self.get_queryset()
        raw_project = request.query_params.get('project')
        if raw_project:
            queryset = queryset.filter(project_id=project_id_from(
                request.query_params, 'project',
            ))
        raw_status = request.query_params.get('status')
        if raw_status:
            queryset = queryset.filter(status=raw_status)
        page = self.paginate_queryset(queryset)
        serializer = self.get_serializer(page, many=True)
        return self.get_paginated_response(serializer.data)

    # -- proposal (owner or site engineer, accepted on the project) -----------

    def proposing_project(self):
        role = self.role()
        if role not in (Role.OWNER, Role.SITE_ENGINEER):
            raise NotAllowed(rules.VO_SURFACE)
        project = scoping.project_or_404(
            self.request.user, role, project_id_from(self.request.data),
        )
        if not (
            scoping.has_accepted_assignment(project, self.request.user, RoleOnProject.OWNER)
            or scoping.has_accepted_assignment(
                project, self.request.user, RoleOnProject.SITE_ENGINEER,
            )
        ):
            raise NotAllowed(rules.SE_OR_OWNER_PROPOSES)
        return project

    def priced_by_owner(self, project):
        """Only the active owner role prices a VO; the site engineer never does."""
        return self.role() == Role.OWNER and scoping.has_accepted_assignment(
            project, self.request.user, RoleOnProject.OWNER,
        )

    def create(self, request, *args, **kwargs):
        project = self.proposing_project()
        serializer = wire.VariationOrderWriteSerializer(data=request.data)
        if not serializer.is_valid():
            return refused(serializer)
        order = billing_services.save_vo(
            request.user, project, serializer.validated_data,
            priced_by_owner=self.priced_by_owner(project),
        )
        return Response(
            wire.VariationOrderSerializer(order).data,
            status=status.HTTP_201_CREATED,
        )

    def partial_update(self, request, *args, **kwargs):
        order = self.get_object()
        project = (
            self.proposing_project() if 'project_id' in request.data else order.project
        )
        if not (
            scoping.has_accepted_assignment(
                project, request.user, RoleOnProject.OWNER,
            ) or scoping.has_accepted_assignment(
                project, request.user, RoleOnProject.SITE_ENGINEER,
            )
        ):
            raise NotAllowed(rules.SE_OR_OWNER_PROPOSES)
        # Merge with the stored values so a one-field edit still validates
        # `type`/`description`; `amount` is only sent when the caller reprices.
        data = {
            'project_id': project.pk,
            'type': request.data.get('type', order.type),
            'description': request.data.get('description', order.description),
            'days_impact': request.data.get('days_impact', order.days_impact),
        }
        if 'amount' in request.data:
            data['amount'] = request.data['amount']
        serializer = wire.VariationOrderWriteSerializer(data=data, partial=True)
        if not serializer.is_valid():
            return refused(serializer)
        order = billing_services.save_vo(
            request.user, project, serializer.validated_data,
            priced_by_owner=self.priced_by_owner(project), vo=order,
        )
        return Response(wire.VariationOrderSerializer(order).data)

    # -- owner moves ----------------------------------------------------------

    def owner_order(self):
        role = self.role()
        if role != Role.OWNER:
            raise NotAllowed(rules.OWNER_PRICING)
        order = self.get_object()
        if not scoping.has_accepted_assignment(
            order.project, self.request.user, RoleOnProject.OWNER,
        ):
            raise NotAllowed(rules.OWNER_PRICING)
        return order

    @action(detail=True, methods=['post'])
    def submit(self, request, pk=None):
        order = billing_services.submit_vo(request.user, self.owner_order())
        return Response(wire.VariationOrderSerializer(order).data)

    @action(detail=True, methods=['post'], url_path='owner-reject')
    def owner_reject(self, request, pk=None):
        order = self.owner_order()
        serializer = wire.ReasonSerializer(data=request.data)
        if not serializer.is_valid():
            return refused(serializer)
        order = billing_services.owner_reject_vo(
            request.user, order, serializer.validated_data['reason'],
        )
        return Response(wire.VariationOrderSerializer(order).data)

    # -- client moves ---------------------------------------------------------

    def client_order(self):
        if self.role() != Role.CLIENT:
            raise NotAllowed(rules.CLIENT_ONLY)
        return self.get_object()

    @action(detail=True, methods=['post'], url_path='client-approve')
    def client_approve(self, request, pk=None):
        order = billing_services.client_approve_vo(request.user, self.client_order())
        return Response(wire.VariationOrderSerializer(order).data)

    @action(detail=True, methods=['post'], url_path='client-reject')
    def client_reject(self, request, pk=None):
        order = self.client_order()
        serializer = wire.ReasonSerializer(data=request.data)
        if not serializer.is_valid():
            return refused(serializer)
        order = billing_services.client_reject_vo(
            request.user, order, serializer.validated_data['reason'],
        )
        return Response(wire.VariationOrderSerializer(order).data)


class RetentionView(APIView):
    """`retention/?project=` — held, released and still available."""

    def get(self, request):
        role = capabilities.active_role(request)
        require_finance(role)
        project = scoping.project_or_404(
            request.user, role, project_id_from(request.query_params, 'project'),
        )
        return Response(billing_services.retention_for(project))


class RetentionReleaseViewSet(viewsets.GenericViewSet, mixins.ListModelMixin):
    """`retention-releases/` — finance reads and the post-completion release."""

    serializer_class = wire.RetentionReleaseSerializer
    http_method_names = ('get', 'post', 'head', 'options')

    def get_queryset(self):
        role = capabilities.active_role(self.request)
        require_finance(role)
        queryset = RetentionRelease.objects.filter(
            project__in=scoping.projects_for(self.request.user, role),
        ).select_related('project')
        raw_project = self.request.query_params.get('project')
        if raw_project:
            queryset = queryset.filter(project_id=project_id_from(
                self.request.query_params, 'project',
            ))
        return queryset

    def create(self, request, *args, **kwargs):
        role = capabilities.active_role(request)
        require_finance(role)
        project = scoping.project_or_404(
            request.user, role, project_id_from(request.data),
        )
        serializer = wire.CreateRetentionReleaseSerializer(data=request.data)
        if not serializer.is_valid():
            return refused(serializer)
        release = billing_services.release_retention(
            request.user, project,
            amount=serializer.validated_data['amount'],
            released_on=serializer.validated_data['released_on'],
            method=serializer.validated_data['method'],
            reference_no=serializer.validated_data.get('reference_no', ''),
        )
        return Response(
            wire.RetentionReleaseSerializer(release).data,
            status=status.HTTP_201_CREATED,
        )
