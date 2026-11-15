"""Read serializers for the 2.2 wire shapes (daily reports, docs, photos).

Shapes are the Flutter models' keys, nothing more. `file_url` is absolute and
ends in the sanitized original file name, because `models/document.dart:44`
reads the display name from the last path segment; the URL is built from the
download route, never from `MEDIA_URL` (files are private).

Redaction: `contract` documents are handled in the views (row hidden + file 404
for non-finance roles), not here, because a serializer cannot refuse a file.
"""

# Pyright here runs without django-stubs/DRF stubs (untyped managers, `Meta`).
# pyright: reportIncompatibleVariableOverride=false, reportAttributeAccessIssue=false

from django.urls import reverse
from rest_framework import serializers

from .models import (
    DailyReport,
    Document,
    EquipmentLog,
    Issue,
    ReportManpower,
    ReportMaterialUsage,
    ReportPhoto,
)


def absolute(request, name, args):
    """The absolute URL for a named route (relative when there is no request)."""
    path = reverse(name, args=args)
    return request.build_absolute_uri(path) if request is not None else path


class DailyReportSerializer(serializers.ModelSerializer):
    class Meta:
        model = DailyReport
        fields = (
            'id', 'project_id', 'report_date', 'weather', 'status',
            'submitted_by', 'reviewed_by', 'remarks', 'toolbox_meeting_held',
            'created_at', 'updated_at',
        )
        read_only_fields = fields


class ReportManpowerSerializer(serializers.ModelSerializer):
    class Meta:
        model = ReportManpower
        fields = (
            'id', 'daily_report_id', 'trade', 'headcount',
            'created_at', 'updated_at',
        )
        read_only_fields = fields


class ReportMaterialUsageSerializer(serializers.ModelSerializer):
    class Meta:
        model = ReportMaterialUsage
        fields = (
            'id', 'daily_report_id', 'material_id', 'quantity',
            'created_at', 'updated_at',
        )
        read_only_fields = fields


class EquipmentLogSerializer(serializers.ModelSerializer):
    class Meta:
        model = EquipmentLog
        fields = (
            'id', 'equipment_id', 'project_id', 'log_date', 'hours_used',
            'daily_report_id', 'created_at', 'updated_at',
        )
        read_only_fields = fields


class IssueSerializer(serializers.ModelSerializer):
    class Meta:
        model = Issue
        fields = (
            'id', 'project_id', 'daily_report_id', 'type', 'reason',
            'description', 'days_lost', 'created_at', 'updated_at',
        )
        read_only_fields = fields


class ReportPhotoSerializer(serializers.ModelSerializer):
    file_url = serializers.SerializerMethodField()

    class Meta:
        model = ReportPhoto
        fields = (
            'id', 'daily_report_id', 'file_url', 'caption', 'latitude',
            'longitude', 'taken_at', 'created_at', 'updated_at',
        )
        read_only_fields = fields

    def get_file_url(self, photo):
        return absolute(
            self.context.get('request'), 'report-photo-file',
            [photo.pk, photo.file_name],
        )


class DocumentSerializer(serializers.ModelSerializer):
    file_url = serializers.SerializerMethodField()

    class Meta:
        model = Document
        fields = (
            'id', 'project_id', 'name', 'doc_type', 'file_url', 'uploaded_by',
            'created_at', 'updated_at',
        )
        read_only_fields = fields

    def get_file_url(self, document):
        return absolute(
            self.context.get('request'), 'document-file',
            [document.pk, document.file_name],
        )


class ReportPhotoWithReportSerializer(serializers.BaseSerializer):
    """`{photo, report}` for `report-photos/approved/` (`client_photos_viewmodel.dart`)."""

    def to_representation(self, instance):
        return {
            'photo': ReportPhotoSerializer(instance, context=self.context).data,
            'report': DailyReportSerializer(instance.daily_report).data,
        }
