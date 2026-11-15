"""
BuildPro CPMS — daily site reports and private project documents (Phase 2.2).

Shapes mirror `flutter/lib/data/models/{daily_report,report_manpower,
report_material_usage,equipment_log,issue,report_photo,document}.dart` — see
`planning/backend-integration/contracts/phase-2-projects-and-site.md`.

App placement is decision 06 #10: a new `apps/site_reports` so the pre-2.2
`apps.site_inventory.EquipmentLog` (movement history, `event_type/site/note`)
keeps its table untouched. `site_reports.EquipmentLog` is the *hours* log the
daily report records; the two never share a table.

Files are private: `Document.file` / `ReportPhoto.file` live under
`MEDIA_ROOT` (never a public URL) with a random stored name, and the sanitized
original name is kept in `file_name` so the download URL can end in it
(`models/document.dart:44` reads the last path segment).

ERD mapping:
    DAILY_REPORT          → apps_site_reports.DailyReport
    REPORT_MANPOWER       → apps_site_reports.ReportManpower
    REPORT_MATERIAL_USAGE → apps_site_reports.ReportMaterialUsage
    EQUIPMENT_LOG (hours) → apps_site_reports.EquipmentLog
    ISSUE                 → apps_site_reports.Issue
    REPORT_PHOTO          → apps_site_reports.ReportPhoto
    DOCUMENT              → apps_site_reports.Document
"""

# Pyright here runs without django-stubs, so model fields and FKs are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

import uuid
from decimal import Decimal
from pathlib import PurePosixPath

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models
from django.db.models.functions import Lower
from django.utils import timezone


def _storage_path(prefix, filename):
    suffix = PurePosixPath(str(filename)).suffix.lower()
    today = timezone.localdate()
    return f'{prefix}/{today:%Y/%m}/{uuid.uuid4().hex}{suffix}'


def document_upload_path(instance, filename):
    """Storage path for a document: `documents/yyyy/mm/<uuid>.<ext>`.

    The random name is what keeps a caller-supplied name from ever reaching the
    filesystem (contract "Uploads"); `file_name` holds the display name.
    """
    return _storage_path('documents', filename)


def photo_upload_path(instance, filename):
    """Storage path for a report photo: `report_photos/yyyy/mm/<uuid>.<ext>`."""
    return _storage_path('report_photos', filename)


class DailyReportStatus(models.TextChoices):
    """Mirror of Flutter `DailyReportStatus`; only draft/returned are editable."""

    DRAFT = 'draft', 'Draft'
    SUBMITTED = 'submitted', 'Submitted'
    APPROVED = 'approved', 'Approved'
    RETURNED = 'returned', 'Returned'


EDITABLE_STATUSES = frozenset({
    DailyReportStatus.DRAFT,
    DailyReportStatus.RETURNED,
})


class Weather(models.TextChoices):
    """Mirror of Flutter `Weather`."""

    SUNNY = 'sunny', 'Sunny'
    CLOUDY = 'cloudy', 'Cloudy'
    LIGHT_RAIN = 'light_rain', 'Light rain'
    HEAVY_RAIN = 'heavy_rain', 'Heavy rain'
    TYPHOON = 'typhoon', 'Typhoon'


class IssueType(models.TextChoices):
    """Mirror of Flutter `IssueType`."""

    DELAY = 'delay', 'Delay'
    SAFETY = 'safety', 'Safety / incident'
    OTHER = 'other', 'Other'


class IssueReason(models.TextChoices):
    """Mirror of Flutter `IssueReason`."""

    RAIN_TYPHOON = 'rain_typhoon', 'Rain / typhoon'
    MATERIAL = 'material', 'Material'
    LABOR = 'labor', 'Labor'
    CLIENT = 'client', 'Client'
    OTHER = 'other', 'Other'


class DocumentType(models.TextChoices):
    """Mirror of Flutter `DocumentType`."""

    CONTRACT = 'contract', 'Contracts'
    PLAN = 'plan', 'Plans'
    PERMIT = 'permit', 'Permits'
    AS_BUILT = 'as_built', 'As-built drawings'
    OTHER = 'other', 'Other'


class DailyReport(models.Model):
    """One day on site: manpower, materials, equipment, issues, photos, to-dos.

    One report per project per date (`contract` "Draft refusals"). `status`
    moves draft → submitted → approved, or submitted → returned → submitted;
    `submitted_by` is the author (set on create, never by the client).
    """

    project = models.ForeignKey(
        'apps_projects.Project',
        on_delete=models.CASCADE,
        related_name='daily_reports',
    )
    report_date = models.DateField()
    weather = models.CharField(max_length=16, choices=Weather.choices)
    status = models.CharField(
        max_length=16,
        choices=DailyReportStatus.choices,
        default=DailyReportStatus.DRAFT,
        db_index=True,
    )
    submitted_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name='daily_reports_submitted',
        help_text='The site engineer who wrote the report (the only editor).',
    )
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='daily_reports_reviewed',
    )
    remarks = models.TextField(
        null=True, blank=True, help_text='Why the owner returned the report.',
    )
    toolbox_meeting_held = models.BooleanField(default=False)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('-report_date', '-id')
        verbose_name = 'Daily report'
        verbose_name_plural = 'Daily reports'
        constraints = [
            models.UniqueConstraint(
                fields=['project', 'report_date'],
                name='unique_report_per_project_date',
            ),
        ]
        indexes = [models.Index(fields=['project', 'report_date'])]

    def __str__(self):
        return f'{self.project_id} {self.report_date} ({self.status})'

    @property
    def is_editable(self):
        return self.status in EDITABLE_STATUSES


class ReportManpower(models.Model):
    """Headcount per trade; `trade` is a name string, not an FK (`report_manpower.dart`)."""

    daily_report = models.ForeignKey(
        DailyReport, on_delete=models.CASCADE, related_name='manpower',
    )
    trade = models.CharField(max_length=120)
    headcount = models.PositiveIntegerField(
        validators=[MinValueValidator(1)],
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('id',)
        verbose_name = 'Report manpower'
        verbose_name_plural = 'Report manpower'

    def __str__(self):
        return f'{self.trade} x{self.headcount}'


class ReportMaterialUsage(models.Model):
    """Material used on the report; approved rows feed site inventory (decision 05)."""

    daily_report = models.ForeignKey(
        DailyReport, on_delete=models.CASCADE, related_name='materials',
    )
    material = models.ForeignKey(
        'apps_master_data.MaterialItem',
        on_delete=models.PROTECT,
        related_name='report_usages',
    )
    quantity = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        validators=[MinValueValidator(Decimal('0.01'))],
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('id',)
        verbose_name = 'Report material usage'
        verbose_name_plural = 'Report material usage'

    def __str__(self):
        return f'{self.material_id} x{self.quantity}'


class EquipmentLog(models.Model):
    """Equipment hours on one report (`equipment_log.dart`), distinct from site_inventory."""

    daily_report = models.ForeignKey(
        DailyReport, on_delete=models.CASCADE, related_name='equipment',
    )
    equipment = models.ForeignKey(
        'apps_master_data.EquipmentItem',
        on_delete=models.PROTECT,
        related_name='report_logs',
    )
    project = models.ForeignKey(
        'apps_projects.Project',
        on_delete=models.CASCADE,
        related_name='equipment_logs',
    )
    log_date = models.DateField(help_text='The report date.')
    hours_used = models.DecimalField(
        max_digits=5,
        decimal_places=2,
        validators=[MinValueValidator(Decimal('0.01'))],
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('id',)
        verbose_name = 'Equipment log (hours)'
        verbose_name_plural = 'Equipment logs (hours)'

    def __str__(self):
        return f'{self.equipment_id} {self.hours_used}h on {self.log_date}'


class Issue(models.Model):
    """A delay/safety/other issue on site; `days_lost` feeds time extensions."""

    daily_report = models.ForeignKey(
        DailyReport,
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name='issues',
    )
    project = models.ForeignKey(
        'apps_projects.Project',
        on_delete=models.CASCADE,
        related_name='issues',
    )
    type = models.CharField(max_length=16, choices=IssueType.choices)
    reason = models.CharField(max_length=16, choices=IssueReason.choices)
    description = models.TextField()
    # A delay can be half a day, so this is decimal like the Flutter model.
    days_lost = models.DecimalField(
        max_digits=6,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('id',)
        verbose_name = 'Issue'
        verbose_name_plural = 'Issues'

    def __str__(self):
        return f'{self.type}/{self.reason}: {self.description[:40]}'


class ReportPhoto(models.Model):
    """A photo on a report; the file is private and served through the API only."""

    daily_report = models.ForeignKey(
        DailyReport, on_delete=models.CASCADE, related_name='photos',
    )
    file = models.FileField(upload_to=photo_upload_path)
    file_name = models.CharField(
        max_length=255, help_text='Sanitized original name; the last URL segment.',
    )
    caption = models.CharField(max_length=255, null=True, blank=True)
    latitude = models.DecimalField(
        max_digits=9, decimal_places=6, null=True, blank=True,
    )
    longitude = models.DecimalField(
        max_digits=9, decimal_places=6, null=True, blank=True,
    )
    taken_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('id',)
        verbose_name = 'Report photo'
        verbose_name_plural = 'Report photos'

    def __str__(self):
        return self.file_name


class Document(models.Model):
    """A project document; contract rows are finance-only (decision 06 #5/#9)."""

    project = models.ForeignKey(
        'apps_projects.Project',
        on_delete=models.CASCADE,
        related_name='documents',
    )
    name = models.CharField(max_length=255)
    doc_type = models.CharField(max_length=16, choices=DocumentType.choices)
    file = models.FileField(upload_to=document_upload_path)
    file_name = models.CharField(
        max_length=255, help_text='Sanitized original name; the last URL segment.',
    )
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name='documents_uploaded',
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('-created_at', '-id')
        verbose_name = 'Document'
        verbose_name_plural = 'Documents'
        constraints = [
            # Same (project, section, name) case-insensitively is refused
            # (mock_document_repository.dart:109-118).
            models.UniqueConstraint(
                Lower('name'), 'project', 'doc_type',
                name='apps_site_reports_document_name_ci_unique',
            ),
        ]

    def __str__(self):
        return f'{self.name} ({self.doc_type})'
