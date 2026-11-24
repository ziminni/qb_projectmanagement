"""Site inventory app views."""

# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportGeneralTypeIssues=false

from decimal import Decimal

from django.db import transaction
from django.db.models import F
from django.utils import timezone
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from ..labor.models import Worker
from ..master_data.models import EquipmentItem, EquipmentOwnership
from ..projects import scoping
from ..projects.models import Category, RoleOnProject
from ..projects.rules import NotAllowed, RuleRefused
from ..projects.services import notify_project_role
from ..users import capabilities
from ..users.models import Role
from ..users.permissions import IsAdminOrReadOnly
from .models import (
    Equipment,
    EquipmentBorrowSource,
    EquipmentBorrowStatus,
    EquipmentLog,
    EquipmentReturnCondition,
    ProjectEquipmentBorrow,
    SiteStock,
    Tool,
)
from .serializers import (
    EquipmentLogSerializer,
    EquipmentSerializer,
    ProjectEquipmentBorrowCreateSerializer,
    ProjectEquipmentBorrowSerializer,
    SiteStockSerializer,
    ToolSerializer,
)


class SiteStockViewSet(viewsets.ModelViewSet):
    """Site stock on hand, filterable per site and by reorder status."""

    queryset = SiteStock.objects.select_related('site').all()
    serializer_class = SiteStockSerializer
    permission_classes = [IsAdminOrReadOnly]

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params

        site = params.get('site')
        if site:
            queryset = queryset.filter(site_id=site)

        search = params.get('search')
        if search:
            queryset = queryset.filter(item_name__icontains=search)

        if params.get('below_reorder_level', '').lower() in ('1', 'true', 'yes'):
            queryset = queryset.filter(quantity_on_hand__lte=F('reorder_level'))

        return queryset


class ToolViewSet(viewsets.ModelViewSet):
    queryset = Tool.objects.select_related('site', 'custodian').all()
    serializer_class = ToolSerializer
    permission_classes = [IsAdminOrReadOnly]

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params

        site = params.get('site')
        if site:
            queryset = queryset.filter(site_id=site)

        condition = params.get('condition')
        if condition:
            queryset = queryset.filter(condition=condition)

        return queryset


class EquipmentViewSet(viewsets.ModelViewSet):
    queryset = Equipment.objects.select_related('site', 'operator').all()
    serializer_class = EquipmentSerializer
    permission_classes = [IsAdminOrReadOnly]

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params

        site = params.get('site')
        if site:
            queryset = queryset.filter(site_id=site)

        status_param = params.get('status')
        if status_param:
            queryset = queryset.filter(status=status_param)

        return queryset


class EquipmentLogViewSet(viewsets.ModelViewSet):
    """Movement / status history for equipment."""

    queryset = EquipmentLog.objects.select_related('equipment', 'site', 'logged_by').all()
    serializer_class = EquipmentLogSerializer
    permission_classes = [IsAdminOrReadOnly]

    def get_queryset(self):
        queryset = super().get_queryset()
        equipment = self.request.query_params.get('equipment')
        if equipment:
            queryset = queryset.filter(equipment_id=equipment)
        return queryset

    def perform_create(self, serializer):
        """Stamp the reporting user as the logger by default."""
        if not serializer.validated_data.get('logged_by'):
            serializer.save(logged_by=self.request.user)
        else:
            serializer.save()


def _first_err(errors):
    for val in errors.values():
        if isinstance(val, list) and val:
            first = val[0]
            return _first_err(first) if isinstance(first, dict) else str(first)
        if isinstance(val, dict):
            return _first_err(val)
    return 'Invalid equipment request.'


class ProjectEquipmentBorrowViewSet(
    mixins.ListModelMixin,
    mixins.CreateModelMixin,
    viewsets.GenericViewSet,
):
    """Project equipment borrowing (Queen Builders own pool + external rental),
    with laborer borrower accountability, PM approval, and return tracking.
    """

    serializer_class = ProjectEquipmentBorrowSerializer

    def role(self):
        return capabilities.active_role(self.request)

    def get_serializer_context(self):
        ctx = super().get_serializer_context()
        ctx['role'] = self.role()
        return ctx

    def get_queryset(self):
        role = self.role()
        if role not in (Role.OWNER, Role.SITE_ENGINEER, Role.ACCOUNTANT, Role.ADMIN):
            raise NotAllowed('Only project staff can view project equipment.')
        projects = scoping.projects_for(self.request.user, role)
        qs = ProjectEquipmentBorrow.objects.filter(
            project__in=projects,
        ).select_related(
            'project',
            'category',
            'equipment_item',
            'borrower_worker__trade',
            'requested_by',
            'reviewed_by',
            'returned_by',
        )
        raw_project = self.request.query_params.get('project')
        if raw_project:
            try:
                qs = qs.filter(project_id=int(raw_project))
            except (TypeError, ValueError) as exc:
                raise RuleRefused('Invalid project filter.') from exc
        raw_status = self.request.query_params.get('status')
        if raw_status:
            qs = qs.filter(status=raw_status)
        return qs

    def _ensure_master_equipment(self, row):
        """Ensure an approved equipment borrow has an EquipmentItem so daily reports can log hours."""
        if row.equipment_item_id:
            return row.equipment_item
        ownership = (
            EquipmentOwnership.RENTED
            if row.source == EquipmentBorrowSource.RENTED
            else EquipmentOwnership.OWNED
        )
        existing = EquipmentItem.objects.filter(
            name__iexact=row.equipment_name.strip(),
        ).first()
        if existing is not None:
            return existing
        return EquipmentItem.objects.create(
            name=row.equipment_name.strip(),
            ownership=ownership,
            rate=row.rental_rate or Decimal('0.00'),
            rate_unit=row.rate_unit or 'day',
        )

    def create(self, request, *args, **kwargs):
        role = self.role()
        if role not in (Role.SITE_ENGINEER, Role.OWNER):
            raise NotAllowed(
                'Only the foreman or project manager can borrow or request equipment.'
            )
        serializer = ProjectEquipmentBorrowCreateSerializer(data=request.data)
        if not serializer.is_valid():
            raise RuleRefused(_first_err(serializer.errors))
        data = serializer.validated_data
        project = scoping.project_or_404(request.user, role, data['project_id'])

        category = None
        if data.get('category_id'):
            category = Category.objects.filter(
                pk=data['category_id'], project=project,
            ).first()
            if category is None:
                raise RuleRefused('Selected Item of Work does not belong to this project.')

        eq_item = None
        if data.get('equipment_item_id'):
            eq_item = EquipmentItem.objects.filter(pk=data['equipment_item_id']).first()
            if eq_item is None:
                raise RuleRefused('Selected equipment item was not found.')

        eq_name = (data.get('equipment_name') or '').strip()
        if eq_item is not None and not eq_name:
            eq_name = eq_item.name
        if not eq_name:
            raise RuleRefused('Choose or enter an equipment name.')

        borrower_worker = None
        borrower_name = (data.get('borrower_name') or '').strip()
        if data.get('borrower_worker_id'):
            borrower_worker = Worker.objects.filter(
                pk=data['borrower_worker_id'],
            ).first()
            if borrower_worker is None:
                raise RuleRefused('Selected laborer was not found.')
            if not borrower_name:
                borrower_name = borrower_worker.full_name

        # If created directly by the PM, deploy immediately as 'borrowed';
        # if requested by the Foreman, start in 'pending' for PM approval.
        is_pm = role == Role.OWNER
        initial_status = (
            EquipmentBorrowStatus.BORROWED
            if is_pm
            else EquipmentBorrowStatus.PENDING
        )

        with transaction.atomic():
            row = ProjectEquipmentBorrow.objects.create(
                project=project,
                category=category,
                equipment_item=eq_item,
                source=data['source'],
                equipment_name=eq_name,
                quantity=data['quantity'],
                borrower_worker=borrower_worker,
                borrower_name=borrower_name,
                rental_supplier=(data.get('rental_supplier') or '').strip(),
                rental_rate=data.get('rental_rate') if is_pm else None,
                rate_unit=data.get('rate_unit') or 'day',
                needed_date=data['needed_date'],
                expected_return_date=data.get('expected_return_date'),
                status=initial_status,
                requested_by=request.user,
                reviewed_by=request.user if is_pm else None,
                notes=(data.get('notes') or '').strip(),
            )
            if is_pm and row.equipment_item_id is None:
                row.equipment_item = self._ensure_master_equipment(row)
                row.save(update_fields=['equipment_item', 'updated_at'])

        if not is_pm:
            notify_project_role(
                project,
                RoleOnProject.OWNER,
                'equipment_request',
                f'{request.user.full_name} requested {row.quantity}x {row.equipment_name} for {project.code}.',
                f'/projects/{project.pk}/equipment',
            )

        return Response(
            self.get_serializer(row).data,
            status=status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=['post'])
    def approve(self, request, pk=None):
        role = self.role()
        if role != Role.OWNER:
            raise NotAllowed('Only the project manager can approve equipment requests.')
        with transaction.atomic():
            row = (
                ProjectEquipmentBorrow.objects.select_for_update()
                .select_related('project', 'equipment_item')
                .get(pk=self.get_object().pk)
            )
            if row.status != EquipmentBorrowStatus.PENDING:
                raise RuleRefused('This equipment request has already been reviewed.')
            if request.data.get('rental_rate') not in (None, ''):
                try:
                    row.rental_rate = Decimal(str(request.data.get('rental_rate'))).quantize(
                        Decimal('0.01')
                    )
                except Exception as exc:
                    raise RuleRefused('Enter a valid rental rate.') from exc
            row.status = EquipmentBorrowStatus.BORROWED
            row.reviewed_by = request.user
            if row.equipment_item_id is None:
                row.equipment_item = self._ensure_master_equipment(row)
            row.save(
                update_fields=[
                    'status',
                    'reviewed_by',
                    'rental_rate',
                    'equipment_item',
                    'updated_at',
                ],
            )
        notify_project_role(
            row.project,
            RoleOnProject.SITE_ENGINEER,
            'equipment_request',
            f'{row.equipment_name} (x{row.quantity}) was approved for {row.project.code}.',
            f'/projects/{row.project_id}/equipment',
        )
        return Response(self.get_serializer(row).data)

    @action(detail=True, methods=['post'])
    def reject(self, request, pk=None):
        role = self.role()
        if role != Role.OWNER:
            raise NotAllowed('Only the project manager can reject equipment requests.')
        reason = str(request.data.get('reason') or '').strip()
        if not reason:
            raise RuleRefused('Enter a reason for rejecting this equipment request.')
        with transaction.atomic():
            row = (
                ProjectEquipmentBorrow.objects.select_for_update()
                .select_related('project')
                .get(pk=self.get_object().pk)
            )
            if row.status != EquipmentBorrowStatus.PENDING:
                raise RuleRefused('This equipment request has already been reviewed.')
            row.status = EquipmentBorrowStatus.REJECTED
            row.reviewed_by = request.user
            row.rejection_reason = reason[:255]
            row.save(
                update_fields=[
                    'status', 'reviewed_by', 'rejection_reason', 'updated_at',
                ],
            )
        notify_project_role(
            row.project,
            RoleOnProject.SITE_ENGINEER,
            'equipment_request',
            f'Equipment request for {row.equipment_name} on {row.project.code} was rejected: {reason}',
            f'/projects/{row.project_id}/equipment',
        )
        return Response(self.get_serializer(row).data)

    @action(detail=True, methods=['post'], url_path='mark-returned')
    def mark_returned(self, request, pk=None):
        role = self.role()
        if role not in (Role.SITE_ENGINEER, Role.OWNER):
            raise NotAllowed('Only the foreman or project manager can mark equipment returned.')
        cond = str(request.data.get('condition') or 'good').strip().lower()
        if cond not in EquipmentReturnCondition.values:
            raise RuleRefused('Choose a valid return condition (good, damaged, or maintenance).')
        return_notes = str(request.data.get('notes') or '').strip()
        with transaction.atomic():
            row = (
                ProjectEquipmentBorrow.objects.select_for_update()
                .select_related('project')
                .get(pk=self.get_object().pk)
            )
            if row.status != EquipmentBorrowStatus.BORROWED:
                raise RuleRefused('Only active on-site equipment can be marked returned.')
            row.status = EquipmentBorrowStatus.RETURNED
            row.return_condition = cond
            row.return_notes = return_notes
            row.returned_at = timezone.now()
            row.returned_by = request.user
            row.save(
                update_fields=[
                    'status',
                    'return_condition',
                    'return_notes',
                    'returned_at',
                    'returned_by',
                    'updated_at',
                ],
            )
        return Response(self.get_serializer(row).data)
