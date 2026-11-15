"""The single contractor company the CPMS serves, plus its settings row.

`Company` is one row per deployment (`Company` in `company.dart`); the
Settings screen's "Licenses and compliance" section edits the same row's PCAB
fields, so there is no separate `License` model.

ERD mapping:
    COMPANY          → apps_company.Company
    COMPANY_SETTINGS → apps_company.CompanySettings
"""

# Pyright here runs without django-stubs, so model fields are inferred as their
# `Field` class (the same suppression `apps/users/models.py` uses).
# pyright: reportAttributeAccessIssue=false

from decimal import Decimal

from django.db import models


class Company(models.Model):
    """Company profile — one row per deployment (`Company` in `company.dart`)."""

    name = models.CharField(max_length=200)
    address = models.TextField(blank=True)
    tin = models.CharField('TIN', max_length=32, blank=True)
    pcab_license_no = models.CharField('PCAB license no.', max_length=64, blank=True)
    # Flutter parses this with the non-null JsonUtils.toDate, so the API always
    # sends a date (see the Phase 1.2 contract, flagged risk 3).
    pcab_license_expiry = models.DateField(null=True, blank=True)
    logo_url = models.URLField(max_length=500, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Company'
        verbose_name_plural = 'Company'

    def __str__(self):
        return str(self.name)


class CompanySettings(models.Model):
    """Default percentages behind the Settings screen (`company_settings.dart`)."""

    company = models.OneToOneField(
        Company,
        on_delete=models.CASCADE,
        related_name='settings',
    )
    default_retention_pct = models.DecimalField(
        max_digits=5, decimal_places=2, default=Decimal('10.00'),
    )
    default_down_payment_pct = models.DecimalField(
        max_digits=5, decimal_places=2, default=Decimal('15.00'),
    )
    behind_schedule_threshold_pct = models.DecimalField(
        max_digits=5, decimal_places=2, default=Decimal('5.00'),
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Company settings'
        verbose_name_plural = 'Company settings'

    def __str__(self):
        return f'Settings for {self.company_id}'
