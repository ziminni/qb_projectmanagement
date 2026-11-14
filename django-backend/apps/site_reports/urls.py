"""Site-reports URL configuration (routed under /api/v1/).

Phase 2.2 routes:

* `daily-reports/` (+ `{id}/submit/`, `{id}/approve/`, `{id}/return/`,
  `{id}/photos/`) — `DailyReportRepository`;
* `report-photos/approved/` and `report-photos/{id}/file/{name}` — the client
  portal's shared photos;
* `documents/{id}/` (DELETE) and `documents/{id}/file/{name}`;
* the project-nested `projects/{id}/documents/`,
  `projects/{id}/approved-material-usage/`,
  `projects/{id}/approved-equipment-logs/`.

The explicit file routes come first so they win over the router's detail paths.
"""

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    DailyReportViewSet,
    DocumentViewSet,
    ReportPhotoViewSet,
    approved_equipment_logs_view,
    approved_material_usage_view,
    document_file_view,
    project_documents_view,
    report_photo_file_view,
)

router = DefaultRouter()
router.register(r'daily-reports', DailyReportViewSet, basename='dailyreport')
router.register(r'report-photos', ReportPhotoViewSet, basename='reportphoto')
router.register(r'documents', DocumentViewSet, basename='document')

urlpatterns = [
    path(
        'projects/<int:pk>/documents/', project_documents_view,
        name='project-documents',
    ),
    path(
        'projects/<int:pk>/approved-material-usage/',
        approved_material_usage_view, name='approved-material-usage',
    ),
    path(
        'projects/<int:pk>/approved-equipment-logs/',
        approved_equipment_logs_view, name='approved-equipment-logs',
    ),
    path(
        'documents/<int:pk>/file/<str:file_name>', document_file_view,
        name='document-file',
    ),
    path(
        'report-photos/<int:pk>/file/<str:file_name>', report_photo_file_view,
        name='report-photo-file',
    ),
    path('', include(router.urls)),
]
