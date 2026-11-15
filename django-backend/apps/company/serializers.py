"""Company profile and settings serializers.

Shapes mirror `flutter/lib/data/models/{company,company_settings}.dart`; refusal
messages are the mock's, verbatim (`MasterDataRules`, `MockCompanyRepository`).
"""

# Pyright here runs without django-stubs/DRF stubs, so `Meta` (the DRF options
# class) reads as an override of ModelSerializer.Meta.
# pyright: reportIncompatibleVariableOverride=false

import re

from rest_framework import serializers

from .models import Company, CompanySettings

# BIR TIN: 000-000-000 with an optional branch code (`master_data_rules.dart:5`).
TIN_PATTERN = re.compile(r'^\d{3}-\d{3}-\d{3}(-\d{3,5})?$')


class CompanySerializer(serializers.ModelSerializer):
    """`Company` (`models/company.dart:47-62`)."""

    name = serializers.CharField(
        max_length=200,
        error_messages={'required': 'Enter the company name.',
                        'blank': 'Enter the company name.'},
    )
    address = serializers.CharField(
        error_messages={'required': 'Enter the address.',
                        'blank': 'Enter the address.'},
    )
    tin = serializers.CharField(
        max_length=32,
        error_messages={'required': 'Enter the TIN.', 'blank': 'Enter the TIN.'},
    )
    pcab_license_no = serializers.CharField(
        max_length=64,
        error_messages={'required': 'Enter the PCAB license number.',
                        'blank': 'Enter the PCAB license number.'},
    )
    pcab_license_expiry = serializers.DateField(
        error_messages={'required': 'Enter the PCAB license expiry.',
                        'null': 'Enter the PCAB license expiry.'},
    )
    logo_url = serializers.URLField(
        max_length=500, allow_null=True, allow_blank=True, required=False,
    )

    class Meta:
        model = Company
        fields = ('id', 'name', 'address', 'tin', 'pcab_license_no',
                  'pcab_license_expiry', 'logo_url', 'created_at', 'updated_at')
        read_only_fields = ('id', 'created_at', 'updated_at')

    def validate_tin(self, value):
        tin = value.strip()
        if not TIN_PATTERN.match(tin):
            raise serializers.ValidationError('Use the format 000-000-000-000.')
        return tin

    def validate_name(self, value):
        return value.strip()

    def validate_address(self, value):
        return value.strip()

    def validate_pcab_license_no(self, value):
        return value.strip()

    def validate_logo_url(self, value):
        return value or None


def percent_field(label):
    """A 0–100 percentage with the mock's messages (`master_data_rules.dart:31-35`)."""
    return serializers.DecimalField(
        max_digits=5, decimal_places=2, allow_null=True, required=False,
        error_messages={'required': f'Enter the {label}.',
                        'invalid': f'Enter the {label}.',
                        'max_digits': f'The {label} must be 0–100%.',
                        'max_decimal_places': f'The {label} must be 0–100%.'},
    )


class CompanySettingsSerializer(serializers.ModelSerializer):
    """`CompanySettings` (`models/company_settings.dart:44-62`)."""

    company_id = serializers.IntegerField(read_only=True)
    default_retention_pct = percent_field('retention')
    default_down_payment_pct = percent_field('down payment')
    behind_schedule_threshold_pct = percent_field('behind-schedule threshold')

    class Meta:
        model = CompanySettings
        fields = ('id', 'company_id', 'default_retention_pct',
                  'default_down_payment_pct', 'behind_schedule_threshold_pct',
                  'created_at', 'updated_at')
        read_only_fields = ('id', 'company_id', 'created_at', 'updated_at')

    def validate_default_retention_pct(self, value):
        return self._check_percent(value, 'retention')

    def validate_default_down_payment_pct(self, value):
        return self._check_percent(value, 'down payment')

    def validate_behind_schedule_threshold_pct(self, value):
        return self._check_percent(value, 'behind-schedule threshold')

    @staticmethod
    def _check_percent(value, label):
        if value is None:
            raise serializers.ValidationError(f'Enter the {label}.')
        if value < 0 or value > 100:
            raise serializers.ValidationError(f'The {label} must be 0–100%.')
        return value


def refusal(serializer):
    """Collapse DRF field errors into the contract's single `detail` string."""
    for messages in serializer.errors.values():
        first = messages[0] if isinstance(messages, list) else messages
        if isinstance(first, dict):
            first = next(iter(first.values()))[0]
        return {'detail': str(first)}
    return {'detail': 'This change was refused.'}
