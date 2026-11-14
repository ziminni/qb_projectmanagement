"""2.2 views — scoped reads, role-checked writes, private file downloads.

Check order everywhere: authentication (global DRF) → **scope** (`404` via
`scoping.projects_for`) → **role/author** (`403`) → business rule (`400`).
Writes live in `services.py`; this file only picks querysets and serializers.

The two file routes are the security boundary for uploads (contract
"Uploads"): they re-check the JWT (global), the active role, the project scope
and — for documents — the `contract` visibility, then stream the stored file
with `Content-Disposition: attachment` (documents) or `inline` (photos),
`X-Content-Type-Options: nosniff` and `Cache-Control: private, no-store`.
"""

# Pyright here runs without django-stubs/DRF stubs (untyped managers, actions).
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportGeneralTypeIssues=false

from datetime import date as date_type
from datetime import datetime, time

from django.http import FileResponse
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status as http_status
from rest_framework.decorators import action, api_view
from rest_framework.exceptions import NotFound, ParseError
from rest_framework.response import Response

from ..projects import scoping
from ..projects.rules import NotAllowed, RuleRefused
from ..projects.serializers import TodoSerializer
from ..projects.views import ScopedViewSet
from ..users import capabilities
from . import rules, services, uploads
from .models import (
    DailyReport,
    DailyReportStatus,
    Document,
    DocumentType,
    EquipmentLog,
    ReportMaterialUsage,
    ReportPhoto,
)
from .serializers import (
    DailyReportSerializer,
    DocumentSerializer,
    EquipmentLogSerializer,
    IssueSerializer,
    ReportManpowerSerializer,
    ReportMaterialUsageSerializer,
    ReportPhotoSerializer,
    ReportPhotoWithReportSerializer,
)


def active_role(request):
    return capabilities.active_role(request)


def require_staff(role, message=rules.REPORTS_STAFF_ONLY):
    """Daily reports and documents are staff-only; the client sees photos only."""
    if role not in capabilities.STAFF_ROLES:
        raise NotAllowed(message)


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


def filter_date(request, name):
    """`?from=2026-11-01` as a date; a junk value is a `400`."""
    raw = request.query_params.get(name)
    if not raw:
        return None
    try:
        return date_type.fromisoformat(str(raw)[:10])
    except ValueError as error:
        raise RuleRefused(f'The {name} filter must be a date.') from error


def _photo_sort_key(photo):
    """Newest first, falling back to the report date (mock order).

    A missing `taken_at` becomes an aware midnight so photos with and without
    one compare as the same type instead of raising.
    """
    moment = photo.taken_at
    if moment is None:
        moment = timezone.make_aware(
            datetime.combine(photo.daily_report.report_date, time.min),
            timezone.get_current_timezone(),
        )
    return (moment, photo.pk)


def detail_payload(report, request):
    """`DailyReportDetail`: the report plus every child list."""
    return {
        'report': DailyReportSerializer(report).data,
        'manpower': ReportManpowerSerializer(report.manpower.all(), many=True).data,
        'materials': ReportMaterialUsageSerializer(
            report.materials.all(), many=True,
        ).data,
        'equipment': EquipmentLogSerializer(report.equipment.all(), many=True).data,
        'issues': IssueSerializer(report.issues.all(), many=True).data,
        'photos': ReportPhotoSerializer(
            report.photos.all(), many=True, context={'request': request},
        ).data,
        'todos': TodoSerializer(
            report.todos.select_related('category'), many=True,
        ).data,
    }


class DailyReportViewSet(ScopedViewSet):
    """`daily-reports/` — list, detail, draft save and the review actions."""

    serializer_class = DailyReportSerializer

    def get_queryset(self):
        return DailyReport.objects.filter(
            project__in=self.projects(),
        ).select_related('project', 'submitted_by', 'reviewed_by')

    def scoped_project(self, raw_id):
        project = scoping.projects_for(self.request.user, self.role()).filter(
            pk=raw_id,
        ).first()
        if project is None:
            raise NotFound()
        return project

    def list(self, request):
        require_staff(self.role())
        queryset = self.get_queryset()
        project_ids = numeric_ids(request, 'project')
        if project_ids:
            queryset = queryset.filter(project_id__in=project_ids)
        status_filter = request.query_params.get('status')
        if status_filter:
            if status_filter not in DailyReportStatus.values:
                raise RuleRefused('Choose a valid status.')
            queryset = queryset.filter(status=status_filter)
        date_from = filter_date(request, 'from')
        if date_from is not None:
            queryset = queryset.filter(report_date__gte=date_from)
        date_to = filter_date(request, 'to')
        if date_to is not None:
            queryset = queryset.filter(report_date__lte=date_to)
        return Response(
            DailyReportSerializer(queryset.order_by('-report_date', '-id'), many=True).data
        )

    def retrieve(self, request, pk=None):
        require_staff(self.role())
        return Response(detail_payload(self.get_object(), request))

    def create(self, request):
        raw_project_id = request.data.get('project_id')
        try:
            project_id = int(str(raw_project_id))
        except (TypeError, ValueError) as error:
            raise RuleRefused('Choose the project.') from error
        report = services.save_draft(
            request.user, self.role(), request.data,
            project=self.scoped_project(project_id),
        )
        return Response(
            DailyReportSerializer(report).data, status=http_status.HTTP_201_CREATED,
        )

    def update(self, request, pk=None):
        report = services.save_draft(
            request.user, self.role(), request.data, report=self.get_object(),
        )
        report.refresh_from_db()
        return Response(DailyReportSerializer(report).data)

    @action(detail=True, methods=['post'])
    def submit(self, request, pk=None):
        report = services.submit(request.user, self.role(), self.get_object())
        return Response(DailyReportSerializer(report).data)

    @action(detail=True, methods=['post'])
    def approve(self, request, pk=None):
        report = services.approve(request.user, self.get_object())
        return Response(DailyReportSerializer(report).data)

    @action(detail=True, methods=['post'], url_path='return')
    def return_report(self, request, pk=None):
        report = services.return_report(
            request.user, self.get_object(), request.data.get('remarks'),
        )
        return Response(DailyReportSerializer(report).data)

    @action(detail=True, methods=['post'], url_path='photos')
    def photos(self, request, pk=None):
        report = self.get_object()
        upload = request.FILES.get('file')
        if upload is None:
            raise ParseError(rules.UPLOAD_FAILED)
        photo = services.upload_photo(request.user, report, upload, request.data)
        return Response(
            ReportPhotoSerializer(photo, context={'request': request}).data,
            status=http_status.HTTP_201_CREATED,
        )


class ReportPhotoViewSet(ScopedViewSet):
    """`report-photos/approved/` — photos of approved reports (the client portal)."""

    serializer_class = ReportPhotoSerializer

    @action(detail=False, methods=['get'])
    def approved(self, request):
        queryset = ReportPhoto.objects.filter(
            daily_report__project__in=self.projects(),
            daily_report__status=DailyReportStatus.APPROVED,
        ).select_related('daily_report', 'daily_report__project')
        project_ids = numeric_ids(request, 'project')
        if project_ids:
            in_scope = set(
                self.projects().filter(pk__in=project_ids).values_list('pk', flat=True)
            )
            if not in_scope:
                raise NotFound()
            queryset = queryset.filter(daily_report__project_id__in=in_scope)
        photos = sorted(queryset, key=_photo_sort_key, reverse=True)
        return Response(
            ReportPhotoWithReportSerializer(
                photos, many=True, context={'request': request},
            ).data
        )


class DocumentViewSet(ScopedViewSet):
    """`documents/{id}/` — delete one document (the list lives on the project)."""

    serializer_class = DocumentSerializer

    def get_queryset(self):
        return Document.objects.filter(
            project__in=self.projects(),
        ).select_related('project')

    def destroy(self, request, pk=None):
        services.delete_document(request.user, self.get_object())
        return Response(status=http_status.HTTP_204_NO_CONTENT)


# --------------------------------------------------------------------------
# Project-nested routes
# --------------------------------------------------------------------------

@api_view(['GET', 'POST'])
def project_documents_view(request, pk):
    """`projects/{id}/documents/` — list (staff) or upload (owner/SE)."""
    role = active_role(request)
    project = scoping.project_or_404(request.user, role, pk)
    if request.method == 'POST':
        # The upload role check (403 for admin/accountant/client) runs inside
        # `upload_document`, so a client sees the same text as the mock.
        upload = request.FILES.get('file')
        if upload is None:
            raise ParseError(rules.UPLOAD_FAILED)
        document = services.upload_document(
            request.user, role, project, upload, request.data,
        )
        return Response(
            DocumentSerializer(document, context={'request': request}).data,
            status=http_status.HTTP_201_CREATED,
        )

    require_staff(role, rules.DOCUMENTS_STAFF_ONLY)
    documents = project.documents.select_related('uploaded_by')
    if not capabilities.sees_finance(role):
        documents = documents.exclude(doc_type=DocumentType.CONTRACT)
    return Response(
        DocumentSerializer(
            documents, many=True, context={'request': request},
        ).data
    )


@api_view(['GET'])
def approved_material_usage_view(request, pk):
    """`projects/{id}/approved-material-usage/` — approved report rows only."""
    role = active_role(request)
    require_staff(role)
    project = scoping.project_or_404(request.user, role, pk)
    rows = ReportMaterialUsage.objects.filter(
        daily_report__project=project,
        daily_report__status=DailyReportStatus.APPROVED,
    ).order_by('id')
    return Response(ReportMaterialUsageSerializer(rows, many=True).data)


@api_view(['GET'])
def approved_equipment_logs_view(request, pk):
    """`projects/{id}/approved-equipment-logs/` — approved report rows only."""
    role = active_role(request)
    require_staff(role)
    project = scoping.project_or_404(request.user, role, pk)
    rows = EquipmentLog.objects.filter(
        daily_report__project=project,
        daily_report__status=DailyReportStatus.APPROVED,
    ).order_by('id')
    return Response(EquipmentLogSerializer(rows, many=True).data)


# --------------------------------------------------------------------------
# Private file downloads
# --------------------------------------------------------------------------

def _download(record, file_name_param, as_attachment):
    """Stream the stored file, refusing a name mismatch before touching disk."""
    if record.file_name != file_name_param:
        raise NotFound()
    path = record.file.path
    extension = uploads.extension_of(record.file_name)
    try:
        handle = open(path, 'rb')  # noqa: SIM115 - closed by FileResponse
    except OSError as error:
        raise NotFound() from error
    response = FileResponse(
        handle,
        as_attachment=as_attachment,
        filename=record.file_name,
        content_type=uploads.content_type(extension),
    )
    response['X-Content-Type-Options'] = 'nosniff'
    response['Cache-Control'] = 'private, no-store'
    return response


@api_view(['GET'])
def document_file_view(request, pk, file_name):
    """`documents/{id}/file/{file_name}` — scoped, contract rows finance-only."""
    role = active_role(request)
    require_staff(role, rules.DOCUMENTS_STAFF_ONLY)
    document = get_object_or_404(Document.objects.select_related('project'), pk=pk)
    scoping.project_or_404(request.user, role, document.project_id)
    if document.doc_type == DocumentType.CONTRACT and not capabilities.sees_finance(role):
        raise NotFound()
    # Documents are never rendered in the browser (CAD and office files alike).
    return _download(document, file_name, as_attachment=True)


@api_view(['GET'])
def report_photo_file_view(request, pk, file_name):
    """`report-photos/{id}/file/{file_name}` — staff, or the client for approved."""
    role = active_role(request)
    photo = get_object_or_404(
        ReportPhoto.objects.select_related('daily_report'), pk=pk,
    )
    scoping.project_or_404(request.user, role, photo.daily_report.project_id)
    if role == 'client' and photo.daily_report.status != DailyReportStatus.APPROVED:
        raise NotFound()
    return _download(photo, file_name, as_attachment=False)
