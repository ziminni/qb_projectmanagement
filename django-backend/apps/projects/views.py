"""Projects app views — scoped reads, role-checked writes (Phase 2 contract).

Order of every check mirrors the contract:

1. authentication (global DRF default);
2. **scope** via `scoping.projects_for()` — out of scope is always `404`;
3. **role** on the resolved object — in scope but wrong role is `403`;
4. the business rule, which answers `400 {"detail": "<mock text>"}`.

Writes live in `services.py`; this file only picks querysets and serializers.
"""

# Pyright here runs without django-stubs/DRF stubs (untyped managers, actions).
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportGeneralTypeIssues=false

from datetime import date, timedelta
from decimal import Decimal
import json
from pathlib import Path
import re

from django.db import transaction
from django.db.models import Sum
from django.http import FileResponse
from django.shortcuts import get_object_or_404
from rest_framework import status, viewsets
from rest_framework.decorators import action, api_view
from rest_framework.filters import OrderingFilter, SearchFilter
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response

from ..master_data.models import MaterialItem
from ..users import capabilities
from ..users import services as user_services
from ..users.models import Role, User
from ..users.permissions import IsAdminOrReadOnly
from . import dupa_importer, scoping, services
from .models import (
    Category,
    Client,
    PlannedMaterial,
    ProjectAssignment,
    ProjectStatus,
    RequestResponse,
    Site,
    Todo,
)
from .rules import CLIENT_WRITE, NotAllowed, RuleRefused, as_decimal
from .serializers import (
    CategorySerializer,
    ClientSerializer,
    PlannedMaterialSerializer,
    ProjectAssignmentSerializer,
    ProjectRequestSerializer,
    ProjectSerializer,
    SiteSerializer,
    TodoSerializer,
    category_weights,
)

# Messages for the writes only an assigned owner may make (*proposed* texts).
SCHEDULE_WRITE = 'Only the owner running this project can change its schedule.'
VERIFY_ONLY = 'Only the owner running this project can verify to-dos.'
TICK_ONLY = 'Only the site engineer or owner assigned to this project can tick to-dos.'


def numeric_filter(request, name):
    """The numeric value of `?<name>=`, or a `400` — never a `ValueError` 500.

    A junk filter (review 2.1 minor 3: `project-assignments/?project=abc`) is a
    caller mistake, so it answers the same `{"detail": ...}` shape as the other
    refusals instead of reaching the ORM.
    """
    value = request.query_params.get(name)
    if not value:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        raise RuleRefused(f'The {name} filter must be a number.')


def as_bool(value):
    """Accept the JSON boolean Flutter sends (and the obvious string forms)."""
    return value in (True, 1, '1', 'true', 'True')


def category_payload(project, role, categories):
    """Render categories with the server-computed weight for this project."""
    return CategorySerializer(
        categories,
        many=True,
        context={'role': role, 'weights': category_weights(project)},
    ).data


class ScopedViewSet(viewsets.GenericViewSet):
    """Shared helpers: the active role and the scoped project queryset."""

    pagination_class = None

    def role(self):
        return capabilities.active_role(self.request)

    def projects(self):
        return scoping.projects_for(self.request.user, self.role())

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context['role'] = self.role()
        return context


class ProjectViewSet(ScopedViewSet):
    """`projects/` — list, detail, create, edit and the request workflow actions."""

    serializer_class = ProjectSerializer

    def get_queryset(self):
        return self.projects().select_related('client')

    def list(self, request):
        services.auto_start_due_projects()
        return Response(
            self.get_serializer(self.get_queryset(), many=True).data
        )

    def retrieve(self, request, pk=None):
        services.auto_start_due_projects()
        return Response(self.get_serializer(self.get_object()).data)

    def create(self, request):
        project = services.create_project(request.user, self.role(), request.data)
        return Response(
            self.get_serializer(project).data, status=status.HTTP_201_CREATED,
        )

    def partial_update(self, request, pk=None):
        project = services.update_project(
            request.user, self.role(), self.get_object(), request.data,
        )
        project.refresh_from_db()
        return Response(self.get_serializer(project).data)

    @action(detail=True, methods=['post'])
    def status(self, request, pk=None):
        """Owner-only manual status move (`projects/{id}/status/`)."""
        project = services.change_status(
            request.user, self.role(), self.get_object(), request.data.get('status'),
        )
        return Response(self.get_serializer(project).data)

    @action(detail=True, methods=['post'])
    def resend(self, request, pk=None):
        """Owner sends a change-requested project back to the client."""
        project = services.resend_request(
            request.user, self.role(), self.get_object(),
        )
        return Response(self.get_serializer(project).data)

    @action(detail=True, methods=['get', 'post'], url_path='assignments')
    def assignments(self, request, pk=None):
        """The project team (staff only), or the owner adding someone."""
        project = self.get_object()
        if request.method == 'GET':
            scoping.require_staff(
                self.role(), 'Only the project team can see who is on the project.',
            )
            return Response(
                ProjectAssignmentSerializer(
                    project.assignments.select_related('user'), many=True,
                ).data
            )
        assignment = services.assign(request.user, self.role(), project, request.data)
        return Response(
            ProjectAssignmentSerializer(assignment).data,
            status=status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=['get', 'post'], url_path='categories')
    def categories(self, request, pk=None):
        project = self.get_object()
        if request.method == 'GET':
            return Response(
                category_payload(project, self.role(), project.categories.all())
            )
        scoping.require_owner(project, request.user, SCHEDULE_WRITE)
        category = services.save_category(project, request.data)
        return Response(
            category_payload(project, self.role(), [category])[0],
            status=status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=['get'])
    def todos(self, request, pk=None):
        project = self.get_object()
        rows = Todo.objects.filter(category__project=project).select_related('category')
        return Response(TodoSerializer(rows, many=True).data)

    @action(detail=True, methods=['post'], url_path='start-timeline')
    def start_timeline(self, request, pk=None):
        """Set the project's actual timeline start date and remap planned W1/W2 bars onto real dates."""
        project = self.get_object()
        scoping.require_owner(project, request.user, SCHEDULE_WRITE)
        raw_date = (request.data.get('start_date') or '').strip()
        try:
            chosen = date.fromisoformat(raw_date[:10])
        except ValueError as exc:
            raise RuleRefused('Provide a valid start_date (YYYY-MM-DD).') from exc

        prev_base = project.timeline_start_date or project.start_date
        with transaction.atomic():
            project.timeline_start_date = chosen
            project.save(update_fields=['timeline_start_date', 'updated_at'])
            for cat in project.categories.all():
                day_offset = cat.day_to_start
                if day_offset is None and cat.start_date and prev_base:
                    day_offset = max(1, (cat.start_date - prev_base).days + 1)
                duration = cat.planned_days
                if duration is None and cat.start_date and cat.end_date:
                    duration = max(1, (cat.end_date - cat.start_date).days + 1)
                if day_offset is not None and duration is not None:
                    new_start = chosen + timedelta(days=day_offset - 1)
                    new_end = new_start + timedelta(days=duration - 1)
                    cat.day_to_start = day_offset
                    cat.planned_days = duration
                    cat.start_date = new_start
                    cat.end_date = new_end
                    cat.save(update_fields=[
                        'day_to_start', 'planned_days', 'start_date', 'end_date', 'updated_at',
                    ])
            user_services.record(
                request.user,
                'timeline_started',
                'project',
                project.pk,
                {'timeline_start_date': chosen.isoformat()},
            )
        return Response(self.get_serializer(project).data)

    _TEMPLATE_VARIANTS = {
        'original': (
            'bar_chart_original.xlsx',
            'DPWH_Bar_Chart_Original_Template.xlsx',
        ),
        'revised': (
            'bar_chart_vo_revised.xlsx',
            'DPWH_Bar_Chart_VO_Revised_Template.xlsx',
        ),
        'combined': (
            'bar_chart_combined.xlsx',
            'DPWH_Bar_Chart_Combined_Template.xlsx',
        ),
    }

    @action(detail=False, methods=['get'], url_path='bar-chart-template')
    def bar_chart_template(self, request):
        """Download the exact DPWH SF-INFR-41 Bar Chart Excel template."""
        variant = (request.query_params.get('variant') or 'combined').strip().lower()
        if variant not in self._TEMPLATE_VARIANTS:
            raise RuleRefused('Unknown template variant. Choose original, revised, or combined.')
        src_name, download_name = self._TEMPLATE_VARIANTS[variant]
        path = Path(__file__).resolve().parent / 'excel_templates' / src_name
        if not path.is_file():
            raise RuleRefused('Template file is not available on the server.')
        return FileResponse(
            path.open('rb'),
            as_attachment=True,
            filename=download_name,
            content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        )

    @action(
        detail=False,
        methods=['post'],
        url_path='preview-items',
        parser_classes=[MultiPartParser, FormParser, JSONParser],
    )
    def preview_items(self, request):
        """Parse a Bar Chart / 3-column Excel before a project exists yet (Create Project wizard)."""
        if self.role() != Role.OWNER:
            raise NotAllowed('Only a project manager can create a project.')
        uploaded = request.FILES.get('file')
        if uploaded is None:
            raise RuleRefused('Upload a Bar Chart Excel (.xlsx) file.')
        raw_start = (
            request.query_params.get('start_date') or request.data.get('start_date') or ''
        ).strip()
        try:
            start_dt = date.fromisoformat(raw_start[:10])
        except ValueError as exc:
            raise RuleRefused('Select a valid Start date before importing the Bar Chart.') from exc
        sheet_name = (
            request.query_params.get('sheet') or request.data.get('sheet') or ''
        ).strip() or None
        try:
            result = dupa_importer.parse_items_schedule_workbook(
                uploaded.read(), start_dt, sheet_name=sheet_name,
            )
        except ValueError as exc:
            raise RuleRefused(str(exc)) from exc
        parsed = result['items']
        if not parsed:
            raise RuleRefused(
                'No Items of Work rows were found. Upload a DPWH SF-INFR-41 Bar Chart '
                'or a 3-column Excel (Item of work, Weeks, Days).'
            )

        end_dates = [i['end_date'] for i in parsed if i.get('end_date') is not None]
        target_end = max(end_dates) if end_dates else start_dt
        total_days = max(1, (target_end - start_dt).days + 1)
        budgets = [i['budget'] for i in parsed if i.get('budget') is not None]
        total_budget = (
            sum(budgets, Decimal('0.00')).quantize(Decimal('0.01'))
            if budgets else None
        )

        return Response({
            'items': [
                {
                    'item_no': item.get('item_no') or '',
                    'name': item['name'],
                    'budget': str(item['budget']) if item.get('budget') is not None else None,
                    'planned_weeks': item['planned_weeks'],
                    'planned_days': item['planned_days'],
                    'day_to_start': item.get('day_to_start'),
                    'start_date': item['start_date'].isoformat() if item['start_date'] else None,
                    'end_date': item['end_date'].isoformat() if item['end_date'] else None,
                }
                for item in parsed
            ],
            'total_items': len(parsed),
            'total_days': total_days,
            'target_end_date': target_end.isoformat(),
            'total_budget': str(total_budget) if total_budget is not None else None,
            'sheet': result['sheet'],
            'sheets': result['sheets'],
            'format': result['format'],
        })

    @action(
        detail=True,
        methods=['post'],
        url_path='import-items',
        parser_classes=[MultiPartParser, FormParser, JSONParser],
    )
    def import_items(self, request, pk=None):
        """Parse (and optionally save) a DPWH SF-INFR-41 Bar Chart or 3-column Excel."""
        project = self.get_object()
        scoping.require_owner(project, request.user, SCHEDULE_WRITE)
        uploaded = request.FILES.get('file')
        if uploaded is None:
            raise RuleRefused(
                'Upload an Excel (.xlsx) Bar Chart or 3-column file (Item of work, Weeks, Days).'
            )
        sheet_name = (
            request.query_params.get('sheet') or request.data.get('sheet') or ''
        ).strip() or None
        base_date = project.timeline_start_date or project.start_date
        try:
            result = dupa_importer.parse_items_schedule_workbook(
                uploaded.read(), base_date, sheet_name=sheet_name,
            )
        except ValueError as exc:
            raise RuleRefused(str(exc)) from exc
        parsed = result['items']
        if not parsed:
            raise RuleRefused(
                'No Items of Work rows were found. Upload a DPWH SF-INFR-41 Bar Chart '
                'or a 3-column Excel (Item of work, Weeks, Days).'
            )

        dry_run = as_bool(
            request.query_params.get('dry_run') or request.data.get('dry_run')
        )
        if dry_run:
            return Response({
                'items': [
                    {
                        'item_no': item.get('item_no') or '',
                        'name': item['name'],
                        'budget': str(item['budget']) if item.get('budget') is not None else None,
                        'planned_weeks': item['planned_weeks'],
                        'planned_days': item['planned_days'],
                        'day_to_start': item.get('day_to_start'),
                        'start_date': item['start_date'].isoformat() if item['start_date'] else None,
                        'end_date': item['end_date'].isoformat() if item['end_date'] else None,
                    }
                    for item in parsed
                ],
                'total_items': len(parsed),
                'sheet': result['sheet'],
                'sheets': result['sheets'],
                'format': result['format'],
            })

        replace_existing = as_bool(
            request.query_params.get('replace') or request.data.get('replace')
        )
        with transaction.atomic():
            if replace_existing:
                project.categories.all().delete()
            next_sort = (project.categories.count() or 0) + 1
            for offset, item in enumerate(parsed):
                Category.objects.create(
                    project=project,
                    item_no=item.get('item_no') or '',
                    name=item['name'],
                    budget=item.get('budget'),
                    planned_weeks=item['planned_weeks'],
                    planned_days=item['planned_days'],
                    day_to_start=item.get('day_to_start'),
                    start_date=item['start_date'],
                    end_date=item['end_date'],
                    sort_order=next_sort + offset,
                )
            user_services.record(
                request.user,
                'items_of_work_imported',
                'project',
                project.pk,
                {
                    'items_imported': len(parsed),
                    'sheet': result['sheet'],
                    'format': result['format'],
                },
            )
        return Response(
            {
                'items_imported': len(parsed),
                'sheet': result['sheet'],
                'categories': category_payload(project, self.role(), project.categories.all()),
            },
            status=status.HTTP_201_CREATED,
        )

    @action(
        detail=True,
        methods=['post'],
        url_path='import-dupa',
        parser_classes=[MultiPartParser, FormParser, JSONParser],
    )
    def import_dupa(self, request, pk=None):
        """Parse (and optionally persist) a DPWH DUPA `.xlsx` workbook."""
        project = self.get_object()
        scoping.require_owner(project, request.user, SCHEDULE_WRITE)
        uploaded = request.FILES.get('file')
        if uploaded is None:
            raise RuleRefused('Upload a DPWH DUPA Excel (.xlsx) file.')
        try:
            parsed = dupa_importer.parse_dupa_xlsx(uploaded.read())
        except ValueError as exc:
            raise RuleRefused(str(exc)) from exc
        if not parsed:
            raise RuleRefused(
                'No DUPA Item of Work sheets were found in that workbook. '
                'Expected sheets with Item No., Section C (Materials), and Total Adjusted Cost.'
            )

        dry_run = as_bool(
            request.query_params.get('dry_run') or request.data.get('dry_run')
        )
        raw_cat_id = request.query_params.get('category_id') or request.data.get('category_id')
        sheet_name = (
            request.query_params.get('sheet') or request.data.get('sheet') or ''
        ).strip() or None
        raw_sheets = request.data.get('sheets')
        selected_sheets = None
        if raw_sheets not in (None, ''):
            if isinstance(raw_sheets, list):
                selected_sheets = {str(s) for s in raw_sheets if str(s)}
            else:
                try:
                    decoded = json.loads(str(raw_sheets))
                    if isinstance(decoded, list):
                        selected_sheets = {str(s) for s in decoded if str(s)}
                except ValueError:
                    selected_sheets = {
                        s.strip() for s in str(raw_sheets).split(',') if s.strip()
                    }

        raw_map = request.data.get('sheet_category_map')
        sheet_category_map = {}
        if raw_map not in (None, ''):
            if isinstance(raw_map, dict):
                raw_dict = raw_map
            else:
                try:
                    raw_dict = json.loads(str(raw_map))
                except ValueError:
                    raw_dict = {}
            if isinstance(raw_dict, dict):
                for k, v in raw_dict.items():
                    try:
                        sheet_category_map[str(k)] = int(v)
                    except (TypeError, ValueError):
                        continue

        target_category = None
        if raw_cat_id not in (None, ''):
            try:
                target_category = get_object_or_404(
                    Category, pk=int(raw_cat_id), project=project,
                )
            except (TypeError, ValueError) as exc:
                raise RuleRefused('Invalid category_id.') from exc

        def _norm_item_no(val):
            return re.sub(r'[^a-z0-9]', '', (val or '').lower())

        project_cats = list(project.categories.all().order_by('sort_order', 'id'))
        cats_by_id = {c.pk: c for c in project_cats}
        existing_by_item_no = {
            _norm_item_no(c.item_no): c
            for c in project_cats
            if c.item_no
        }

        def _match_category(item):
            if target_category is not None:
                return target_category
            explicit_id = sheet_category_map.get(item['sheet'])
            if explicit_id and explicit_id in cats_by_id:
                return cats_by_id[explicit_id]
            if item['item_no']:
                hit = existing_by_item_no.get(_norm_item_no(item['item_no']))
                if hit is not None:
                    return hit
            return None

        available_sheets = [item['sheet'] for item in parsed]
        selected_sheet = None
        if target_category is not None:
            chosen = None
            if sheet_name:
                for item in parsed:
                    if item['sheet'] == sheet_name:
                        chosen = item
                        break
            if chosen is None and target_category.item_no:
                want = _norm_item_no(target_category.item_no)
                for item in parsed:
                    if _norm_item_no(item['item_no']) == want:
                        chosen = item
                        break
            if chosen is None:
                chosen = parsed[0]
            selected_sheet = chosen['sheet']
            parsed = [chosen]
        elif selected_sheets is not None:
            parsed = [item for item in parsed if item['sheet'] in selected_sheets]
            if not parsed:
                raise RuleRefused('Select at least one Item of Work to import.')

        total_materials = sum(len(item['materials']) for item in parsed)
        total_budget = sum(
            (item['budget'] or Decimal('0.00')) for item in parsed
        )

        if dry_run:
            preview_items = []
            matched_cat_ids = set()
            for item in parsed:
                matched = _match_category(item)
                if matched is not None:
                    matched_cat_ids.add(matched.pk)
                preview_items.append({
                    'sheet': item['sheet'],
                    'item_no': item['item_no'],
                    'name': item['name'],
                    'budget': str(item['budget']) if item['budget'] is not None else None,
                    'labor_budget': str(item['labor_budget']) if item['labor_budget'] is not None else None,
                    'equipment_budget': str(item['equipment_budget']) if item['equipment_budget'] is not None else None,
                    'material_budget': str(item['material_budget']) if item['material_budget'] is not None else None,
                    'dupa_breakdown': item['dupa_breakdown'],
                    'matched_category_id': matched.pk if matched is not None else None,
                    'matched_category_name': matched.name if matched is not None else None,
                    'matched_item_no': matched.item_no if matched is not None else None,
                    'materials': [
                        {
                            'name': m['name'],
                            'unit': m['unit'],
                            'planned_qty': str(m['planned_qty']),
                            'unit_cost': str(m['unit_cost']),
                            'amount': str((m['planned_qty'] * m['unit_cost']).quantize(Decimal('0.01'))),
                        }
                        for m in item['materials']
                    ],
                })
            return Response({
                'items': preview_items,
                'total_items': len(parsed),
                'total_materials': total_materials,
                'total_budget': str(total_budget.quantize(Decimal('0.01'))),
                'sheet': selected_sheet,
                'sheets': available_sheets if target_category is not None else [],
                'project_categories': [
                    {
                        'id': c.pk,
                        'item_no': c.item_no,
                        'name': c.name,
                        'has_dupa': bool(c.dupa_breakdown),
                    }
                    for c in project_cats
                ],
                'matched_count': len(matched_cat_ids),
            })

        master_by_name = {
            m.name.strip().lower(): m
            for m in MaterialItem.objects.all()
        }
        next_sort = (project.categories.count() or 0) + 1
        created_categories = []
        created_materials = 0

        with transaction.atomic():
            for offset, item in enumerate(parsed):
                matched = _match_category(item)
                if matched is not None:
                    category = matched
                    if item['budget'] is not None:
                        category.budget = item['budget']
                    category.labor_budget = item['labor_budget']
                    category.equipment_budget = item['equipment_budget']
                    category.material_budget = item['material_budget']
                    category.dupa_breakdown = item['dupa_breakdown']
                    if not category.item_no and item['item_no']:
                        category.item_no = item['item_no']
                    category.save(update_fields=[
                        'item_no', 'budget', 'labor_budget',
                        'equipment_budget', 'material_budget',
                        'dupa_breakdown', 'updated_at',
                    ])
                    PlannedMaterial.objects.filter(project=project, category=category).delete()
                else:
                    category = Category.objects.create(
                        project=project,
                        item_no=item['item_no'],
                        name=item['name'],
                        budget=item['budget'],
                        labor_budget=item['labor_budget'],
                        equipment_budget=item['equipment_budget'],
                        material_budget=item['material_budget'],
                        dupa_breakdown=item['dupa_breakdown'],
                        sort_order=next_sort + offset,
                    )
                created_categories.append(category)
                for m_idx, mat in enumerate(item['materials'], start=1):
                    master = master_by_name.get(mat['name'].strip().lower())
                    PlannedMaterial.objects.create(
                        project=project,
                        category=category,
                        material_item=master,
                        name=mat['name'],
                        unit=mat['unit'],
                        planned_qty=mat['planned_qty'],
                        unit_cost=mat['unit_cost'],
                        sort_order=m_idx,
                    )
                    created_materials += 1

            user_services.record(
                request.user,
                'dupa_imported',
                'project',
                project.pk,
                {
                    'items_imported': len(created_categories),
                    'materials_imported': created_materials,
                },
            )

        return Response(
            {
                'items_imported': len(created_categories),
                'materials_imported': created_materials,
                'total_budget': str(total_budget.quantize(Decimal('0.01'))),
                'categories': category_payload(project, self.role(), project.categories.all()),
            },
            status=status.HTTP_201_CREATED,
        )


class ProjectAssignmentViewSet(ScopedViewSet):
    """`project-assignments/` — list a user's rows, remove one, answer a request."""

    serializer_class = ProjectAssignmentSerializer

    def get_queryset(self):
        queryset = ProjectAssignment.objects.select_related('project', 'user')
        if self.role() == Role.ADMIN:
            return queryset
        return queryset.filter(user=self.request.user)

    def list(self, request):
        role = self.role()
        user_param = request.query_params.get('user')
        if role != Role.ADMIN and user_param and str(request.user.pk) != str(user_param):
            raise NotAllowed('You can only see your own assignments.')
        queryset = self.get_queryset()
        user_id = numeric_filter(request, 'user')
        if user_id is not None:
            queryset = queryset.filter(user_id=user_id)
        project_id = numeric_filter(request, 'project')
        if project_id is not None:
            queryset = queryset.filter(project_id=project_id)
        for name in ('role_on_project', 'response'):
            value = request.query_params.get(name)
            if value:
                queryset = queryset.filter(**{name: value})
        return Response(ProjectAssignmentSerializer(queryset, many=True).data)

    def destroy(self, request, pk=None):
        assignment = get_object_or_404(ProjectAssignment.objects.select_related('project'), pk=pk)
        role = self.role()
        if role != Role.ADMIN:
            scoping.project_or_404(request.user, role, assignment.project_id)
            scoping.require_owner(
                assignment.project, request.user,
                'Only the owner running this project can remove people from it.',
            )
        services.unassign(request.user, assignment)
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=['post'])
    def respond(self, request, pk=None):
        """The assignee answers their own request (any other user gets `404`)."""
        assignment = get_object_or_404(
            ProjectAssignment.objects.select_related('project'), pk=pk,
        )
        assignment = services.respond(
            request.user, self.role(), assignment, request.data,
        )
        return Response(ProjectAssignmentSerializer(assignment).data)


class ProjectRequestViewSet(ScopedViewSet):
    """`project-requests/` — the caller's pending requests in the active role."""

    serializer_class = ProjectRequestSerializer

    def list(self, request):
        rows = (
            ProjectAssignment.objects
            .filter(
                user=request.user,
                role_on_project=self.role(),
                response=RequestResponse.PENDING,
            )
            .exclude(project__status=ProjectStatus.DECLINED)
            .select_related('project')
            .order_by('pk')
        )
        return Response(
            ProjectRequestSerializer(
                rows, many=True, context={'role': self.role()},
            ).data
        )


class CategoryViewSet(ScopedViewSet):
    """`categories/{id}/` — edit or delete one category."""

    serializer_class = CategorySerializer

    def get_queryset(self):
        return Category.objects.filter(
            project__in=self.projects(),
        ).select_related('project')

    def partial_update(self, request, pk=None):
        category = self.get_object()
        scoping.require_owner(category.project, request.user, SCHEDULE_WRITE)
        services.save_category(category.project, request.data, category=category)
        return Response(
            category_payload(category.project, self.role(), [category])[0]
        )

    def destroy(self, request, pk=None):
        category = self.get_object()
        scoping.require_owner(category.project, request.user, SCHEDULE_WRITE)
        services.delete_category(category)
        return Response(status=status.HTTP_204_NO_CONTENT)


class PlannedMaterialViewSet(ScopedViewSet):
    """`planned-materials/` — Bill of Materials (DUPA Section C) per project."""

    serializer_class = PlannedMaterialSerializer

    def get_queryset(self):
        queryset = PlannedMaterial.objects.filter(
            project__in=self.projects(),
        ).select_related('project', 'category', 'material_item')
        project_id = numeric_filter(self.request, 'project')
        if project_id is not None:
            queryset = queryset.filter(project_id=project_id)
        category_id = numeric_filter(self.request, 'category')
        if category_id is not None:
            queryset = queryset.filter(category_id=category_id)
        return queryset

    def _usage_context(self, project_ids):
        from ..requisitions.models import (
            DeliveryItem,
            MaterialRequestItem,
            MaterialRequestStatus,
        )

        req_by_planned_id = {}
        req_by_name = {}
        deliv_by_name = {}
        if project_ids:
            req_rows = (
                MaterialRequestItem.objects.filter(
                    material_request__project_id__in=project_ids,
                )
                .exclude(material_request__status=MaterialRequestStatus.REJECTED)
                .values_list('planned_material_id', 'description', 'quantity_requested')
            )
            for pm_id, desc, qty in req_rows:
                q = qty or Decimal('0.00')
                if pm_id:
                    req_by_planned_id[pm_id] = req_by_planned_id.get(pm_id, Decimal('0.00')) + q
                else:
                    key = (desc or '').strip().lower()
                    if key:
                        req_by_name[key] = req_by_name.get(key, Decimal('0.00')) + q

            deliv_rows = (
                DeliveryItem.objects.filter(
                    purchase_order_item__purchase_order__project_id__in=project_ids,
                )
                .values_list('purchase_order_item__description', 'qty_received')
            )
            for desc, qty in deliv_rows:
                key = (desc or '').strip().lower()
                if key:
                    deliv_by_name[key] = deliv_by_name.get(key, Decimal('0.00')) + (qty or Decimal('0.00'))

        return {
            **self.get_serializer_context(),
            'requested_by_planned_id': req_by_planned_id,
            'requested_by_name': req_by_name,
            'delivered_by_name': deliv_by_name,
        }

    def list(self, request):
        rows = list(self.get_queryset())
        project_ids = list({r.project_id for r in rows})
        ctx = self._usage_context(project_ids)
        return Response(PlannedMaterialSerializer(rows, many=True, context=ctx).data)

    def _clean_fields(self, data, instance=None):
        name = str(data.get('name', instance.name if instance else '') or '').strip()
        if not name:
            raise RuleRefused('Enter the material name.')
        unit = str(data.get('unit', instance.unit if instance else 'pcs') or '').strip() or 'pcs'
        qty = as_decimal(data.get('planned_qty', instance.planned_qty if instance else None))
        if qty is None or qty <= 0:
            raise RuleRefused('Planned quantity must be greater than zero.')
        unit_cost = as_decimal(data.get('unit_cost', instance.unit_cost if instance else Decimal('0.00')))
        if unit_cost is None or unit_cost < 0:
            raise RuleRefused('Unit cost cannot be negative.')
        return {
            'name': name[:255],
            'unit': unit[:32],
            'planned_qty': qty.quantize(Decimal('0.01')),
            'unit_cost': unit_cost.quantize(Decimal('0.01')),
        }

    def create(self, request):
        project_id = request.data.get('project_id')
        project = scoping.project_or_404(request.user, self.role(), project_id)
        scoping.require_owner(project, request.user, SCHEDULE_WRITE)
        category = None
        cat_id = request.data.get('category_id')
        if cat_id:
            category = get_object_or_404(Category, pk=cat_id, project=project)
        fields = self._clean_fields(request.data)
        master = MaterialItem.objects.filter(name__iexact=fields['name']).first()
        row = PlannedMaterial.objects.create(
            project=project,
            category=category,
            material_item=master,
            sort_order=project.planned_materials.count() + 1,
            **fields,
        )
        ctx = self._usage_context([project.pk])
        return Response(
            PlannedMaterialSerializer(row, context=ctx).data,
            status=status.HTTP_201_CREATED,
        )

    def partial_update(self, request, pk=None):
        row = self.get_object()
        scoping.require_owner(row.project, request.user, SCHEDULE_WRITE)
        fields = self._clean_fields(request.data, instance=row)
        if 'category_id' in request.data:
            cat_id = request.data.get('category_id')
            row.category = (
                get_object_or_404(Category, pk=cat_id, project=row.project)
                if cat_id
                else None
            )
        for k, v in fields.items():
            setattr(row, k, v)
        row.save()
        ctx = self._usage_context([row.project_id])
        return Response(PlannedMaterialSerializer(row, context=ctx).data)

    def update(self, request, pk=None):
        return self.partial_update(request, pk)

    def destroy(self, request, pk=None):
        row = self.get_object()
        scoping.require_owner(row.project, request.user, SCHEDULE_WRITE)
        row.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class TodoViewSet(ScopedViewSet):
    """`todos/` — create, edit, delete, tick, verify and un-verify."""

    serializer_class = TodoSerializer

    def get_queryset(self):
        return Todo.objects.filter(
            category__project__in=self.projects(),
        ).select_related('category', 'category__project')

    def category_in_project(self, raw_category_id, project=None):
        """Resolve the body's `category_id` inside the caller's scope, else 404."""
        category = get_object_or_404(
            Category.objects.select_related('project'), pk=raw_category_id,
        )
        if project is not None and category.project_id != project.pk:
            from rest_framework.exceptions import NotFound

            raise NotFound()
        scoping.project_or_404(
            self.request.user, self.role(), category.project_id,
        )
        return category

    def create(self, request):
        category = self.category_in_project(request.data.get('category_id'))
        scoping.require_owner(category.project, request.user, SCHEDULE_WRITE)
        todo = services.save_todo(category, request.data)
        return Response(TodoSerializer(todo).data, status=status.HTTP_201_CREATED)

    def partial_update(self, request, pk=None):
        todo = self.get_object()
        project = todo.category.project
        scoping.require_owner(project, request.user, SCHEDULE_WRITE)
        category = todo.category
        if 'category_id' in request.data:
            category = self.category_in_project(request.data.get('category_id'), project)
        todo = services.save_todo(category, request.data, todo=todo)
        return Response(TodoSerializer(todo).data)

    def destroy(self, request, pk=None):
        todo = self.get_object()
        scoping.require_owner(todo.category.project, request.user, SCHEDULE_WRITE)
        services.delete_todo(todo)
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=['post'])
    def done(self, request, pk=None):
        todo = self.get_object()
        scoping.require_owner_or_site_engineer(
            todo.category.project, request.user, self.role(), TICK_ONLY,
        )
        todo = services.set_todo_done(request.user, todo, as_bool(request.data.get('done')))
        return Response(TodoSerializer(todo).data)

    @action(detail=True, methods=['post'])
    def verify(self, request, pk=None):
        todo = self.get_object()
        scoping.require_owner(todo.category.project, request.user, VERIFY_ONLY)
        todo = services.verify_todo(request.user, todo)
        return Response(TodoSerializer(todo).data)

    @action(detail=True, methods=['post'])
    def unverify(self, request, pk=None):
        todo = self.get_object()
        scoping.require_owner(todo.category.project, request.user, VERIFY_ONLY)
        todo = services.unverify_todo(request.user, todo, request.data.get('reason'))
        return Response(TodoSerializer(todo).data)


class ClientViewSet(ScopedViewSet):
    """`clients/` — client records for the project form and the client-link.

    Reads stay staff-only (the project form picks `client_id`). Create and edit
    are the Admin/Owner active role's, per task 5.3; the Accountant keeps read
    access. There is no delete route: `Project.client` protects the row and a
    login link must be removable without destroying the record.
    """

    serializer_class = ClientSerializer

    def get_queryset(self):
        return Client.objects.select_related('user')

    def _require_writer(self):
        scoping.require_client_writer(self.role(), CLIENT_WRITE)

    def list(self, request):
        scoping.require_staff(self.role(), 'Client records are staff-only.')
        # Ensure every active client-role user has a Client profile so newly
        # created client accounts always show up in the project form dropdown.
        linked_user_ids = set(
            Client.objects.exclude(user_id__isnull=True)
            .values_list('user_id', flat=True),
        )
        for u in User.objects.filter(
            is_active=True, user_roles__role=Role.CLIENT,
        ).distinct():
            if u.pk in linked_user_ids:
                continue
            unlinked = Client.objects.filter(
                user__isnull=True, email__iexact=u.email,
            ).first()
            if unlinked is not None:
                unlinked.user = u
                unlinked.save(update_fields=['user', 'updated_at'])
            else:
                Client.objects.create(
                    name=u.full_name,
                    contact_person=u.full_name,
                    email=u.email,
                    phone=u.phone,
                    user=u,
                )
        return Response(ClientSerializer(self.get_queryset(), many=True).data)

    def retrieve(self, request, pk=None):
        scoping.require_staff(self.role(), 'Client records are staff-only.')
        return Response(ClientSerializer(self.get_object()).data)

    def create(self, request):
        self._require_writer()
        client = services.create_client(request.user, request.data)
        return Response(
            ClientSerializer(client).data, status=status.HTTP_201_CREATED,
        )

    def partial_update(self, request, pk=None):
        self._require_writer()
        client = services.update_client(request.user, self.get_object(), request.data)
        return Response(ClientSerializer(client).data)

    def update(self, request, pk=None):
        return self.partial_update(request, pk)

    @action(detail=True, methods=['post'], url_path='link-user')
    def link_user(self, request, pk=None):
        """Attach a client-role portal login to this client (one per client)."""
        self._require_writer()
        client = services.link_client_user(
            request.user, self.get_object(), request.data.get('user_id'),
        )
        return Response(ClientSerializer(client).data)

    @action(detail=True, methods=['post'], url_path='unlink-user')
    def unlink_user(self, request, pk=None):
        self._require_writer()
        client = services.unlink_client_user(request.user, self.get_object())
        return Response(ClientSerializer(client).data)


class SiteViewSet(viewsets.ModelViewSet):
    """`sites/` — unchanged Phase 3 tenant; kept for `site_inventory`/`requisitions`."""

    queryset = Site.objects.all()
    serializer_class = SiteSerializer
    permission_classes = [IsAdminOrReadOnly]
    filter_backends = [SearchFilter, OrderingFilter]
    search_fields = ['code', 'name', 'city', 'province']
    ordering_fields = ['code', 'name', 'status', 'created_at']
    ordering = ['code']

    def get_queryset(self):
        queryset = super().get_queryset()
        status_param = self.request.query_params.get('status')
        if status_param:
            queryset = queryset.filter(status=status_param)
        return queryset


@api_view(['PUT'])
def user_assignments_view(request, pk):
    """`users/{id}/assignments/` — an admin replaces one user's projects."""
    if capabilities.active_role(request) != Role.ADMIN:
        raise NotAllowed('Admin role required.')
    target = get_object_or_404(User, pk=pk)
    rows = request.data.get('assignments') or []
    assignments = services.set_user_assignments(request.user, target, rows)
    return Response(ProjectAssignmentSerializer(assignments, many=True).data)
