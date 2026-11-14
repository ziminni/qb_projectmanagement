"""Company profile and settings views (Phase 1.2 contract).

Both are singletons of the caller's own company: there is no id in the path,
so a caller can never name another company's row.

Audit rows are written by the server inside the same transaction as the change
(`apps.users.services.record`), so the desktop cannot forge them.
"""

# Pyright here runs without django-stubs or DRF type stubs, so validated_data and
# transaction.atomic() are inferred loosely; `manage.py check` and the tests gate.
# pyright: reportGeneralTypeIssues=false, reportAttributeAccessIssue=false, reportArgumentType=false

from django.db import transaction
from django.http import Http404
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from ..users import services
from .models import Company, CompanySettings
from .permissions import IsAdminOrAnyRoleRead, IsAdminOrStaffRead
from .serializers import CompanySerializer, CompanySettingsSerializer, refusal


def caller_company(request):
    """The row this deployment serves (one `Company` per install)."""
    company = Company.objects.filter(pk=request.user.company_id).first()
    if company is None:
        raise Http404('No company is configured for this account.')
    return company


class CompanyView(APIView):
    """`GET company/` (any role) and `PATCH company/` (admin)."""

    permission_classes = [IsAdminOrAnyRoleRead]

    def get(self, request):
        return Response(CompanySerializer(caller_company(request)).data)

    def patch(self, request):
        company = caller_company(request)
        serializer = CompanySerializer(company, data=request.data, partial=True)
        if not serializer.is_valid():
            return Response(refusal(serializer),
                            status=status.HTTP_400_BAD_REQUEST)
        with transaction.atomic():
            company = serializer.save()
            services.record(request.user, 'company_profile_updated', 'company',
                            company.pk, {'name': company.name})
        return Response(CompanySerializer(company).data)


class CompanySettingsView(APIView):
    """`GET company-settings/` (staff) and `PATCH company-settings/` (admin)."""

    permission_classes = [IsAdminOrStaffRead]

    def get(self, request):
        # Read-only (review 1.2 minor 3): migration 0004 seeds the row for every
        # company, so a read never creates one. The unsaved default row below is
        # only reached if a company was inserted outside the migrations.
        company = caller_company(request)
        settings = CompanySettings.objects.filter(company=company).first()
        if settings is None:
            settings = CompanySettings(company=company)
        return Response(CompanySettingsSerializer(settings).data)

    def patch(self, request):
        # Created on the first save, not on a read.
        settings, _ = CompanySettings.objects.get_or_create(
            company=caller_company(request),
        )
        serializer = CompanySettingsSerializer(settings, data=request.data,
                                              partial=True)
        if not serializer.is_valid():
            return Response(refusal(serializer),
                            status=status.HTTP_400_BAD_REQUEST)
        with transaction.atomic():
            serializer.save()
            services.record(request.user, 'settings_updated',
                            'company_settings', settings.pk, {
                                'retention_pct': float(settings.default_retention_pct),
                                'down_payment_pct': float(settings.default_down_payment_pct),
                                'behind_schedule_pct': float(
                                    settings.behind_schedule_threshold_pct),
                            })
        return Response(CompanySettingsSerializer(settings).data)
