"""Labor serializers: worker rows and the save-day payload.

Finance redaction here is **omission**, not zeroing: the contract says a
non-finance role must not receive `daily_rate` or any government identifier,
and absence is not an authoritative zero. The Flutter worker model currently
decodes a missing `daily_rate` as a parse error, so the HTTP worker adapter is a
later slice (contract "Boundary").

`trade` is the Trade's name on the wire, never its numeric id; writes resolve
an existing master-data name.
"""

# Pyright here runs without django-stubs/DRF stubs.
# pyright: reportAttributeAccessIssue=false, reportOptionalMemberAccess=false, reportIncompatibleVariableOverride=false

import re
from datetime import date
from decimal import Decimal

from rest_framework import serializers

from ..master_data.models import Trade
from ..users import capabilities
from . import rules
from .models import Attendance, AttendanceStatus, Worker

ISO_DATE_RE = re.compile(r'\d{4}-\d{2}-\d{2}')


def parse_iso_date(raw):
    """`'YYYY-MM-DD'` as a date; `ValueError` for anything else (strict)."""
    if not isinstance(raw, str) or not ISO_DATE_RE.fullmatch(raw):
        raise ValueError('not an ISO date')
    return date.fromisoformat(raw)


class StrictISODateField(serializers.DateField):
    """A date field that refuses `2026-3-2` and `20260302`.

    DRF's own `DateField` accepts both; the labor contract asks for strict
    ISO dates so a typo is a refusal, not a guess.
    """

    def to_internal_value(self, data):
        try:
            return parse_iso_date(data)
        except (TypeError, ValueError):
            self.fail('invalid')


class StrictBooleanField(serializers.BooleanField):
    """Accept the JSON booleans only — not `"true"`, `1` or `"no"`."""

    default_error_messages = {'invalid': 'Enter true or false.'}

    def to_internal_value(self, data):
        if not isinstance(data, bool):
            self.fail('invalid')
        return data


class StrictIntegerField(serializers.IntegerField):
    """An integer field that refuses JSON booleans (`true` is not `1`)."""

    def to_internal_value(self, data):
        if isinstance(data, bool):
            self.fail('invalid')
        return super().to_internal_value(data)


def sees_finance(context):
    request = context.get('request')
    if request is None or not request.user.is_authenticated:
        return False
    return capabilities.sees_finance(capabilities.active_role(request))


class WorkerSerializer(serializers.ModelSerializer):
    """`Worker` (`models/worker.dart:4-18`), complete for finance roles."""

    full_name = serializers.CharField(
        max_length=200,
        error_messages={'required': rules.WORKER_NAME,
                        'blank': rules.WORKER_NAME},
    )
    trade = serializers.CharField(
        max_length=200,
        error_messages={'required': rules.WORKER_TRADE,
                        'blank': rules.WORKER_TRADE},
    )
    daily_rate = serializers.DecimalField(
        max_digits=12, decimal_places=2,
        error_messages={'required': rules.RATE_POSITIVE,
                        'invalid': rules.RATE_INVALID,
                        'max_digits': rules.RATE_INVALID,
                        'max_decimal_places': rules.RATE_PRECISION},
    )
    sss_no = serializers.CharField(
        max_length=32, allow_null=True, allow_blank=True, required=False,
    )
    philhealth_no = serializers.CharField(
        max_length=32, allow_null=True, allow_blank=True, required=False,
    )
    pagibig_no = serializers.CharField(
        max_length=32, allow_null=True, allow_blank=True, required=False,
    )
    is_active = StrictBooleanField(required=False)

    class Meta:
        model = Worker
        fields = ('id', 'full_name', 'trade', 'daily_rate', 'sss_no',
                  'philhealth_no', 'pagibig_no', 'is_active', 'created_at',
                  'updated_at')
        read_only_fields = ('id', 'created_at', 'updated_at')

    def validate_full_name(self, value):
        name = value.strip()
        if not name:
            raise serializers.ValidationError(rules.WORKER_NAME)
        return name

    def validate_trade(self, value):
        name = value.strip()
        if not name:
            raise serializers.ValidationError(rules.WORKER_TRADE)
        trade = Trade.objects.filter(name__iexact=name).first()
        if trade is None:
            raise serializers.ValidationError(rules.WORKER_TRADE)
        return trade

    def validate_daily_rate(self, value):
        if value <= 0:
            raise serializers.ValidationError(rules.RATE_POSITIVE)
        return value

    def validate(self, attrs):
        attrs = super().validate(attrs)
        if self.instance is None and 'daily_rate' not in attrs:
            raise serializers.ValidationError({'daily_rate': rules.RATE_POSITIVE})
        return attrs

    def validate_sss_no(self, value):
        return (value or '').strip() or None

    def validate_philhealth_no(self, value):
        return (value or '').strip() or None

    def validate_pagibig_no(self, value):
        return (value or '').strip() or None

    def to_representation(self, instance):
        data = super().to_representation(instance)
        data['trade'] = instance.trade.name
        if not sees_finance(self.context):
            for key in ('daily_rate', 'sss_no', 'philhealth_no', 'pagibig_no'):
                data.pop(key, None)
        return data


class AttendanceEntrySerializer(serializers.Serializer):
    """One row of a save-day sheet."""

    worker_id = StrictIntegerField(
        min_value=1,
        error_messages={'required': rules.UNKNOWN_WORKER,
                        'invalid': rules.UNKNOWN_WORKER,
                        'null': rules.UNKNOWN_WORKER},
    )
    status = serializers.ChoiceField(
        choices=AttendanceStatus.choices,
        error_messages={'invalid_choice': rules.ENTRY_STATUS},
    )
    overtime_hours = serializers.DecimalField(
        max_digits=4, decimal_places=2, min_value=0, max_value=12,
        required=False, default=Decimal(0),
        error_messages={'invalid': rules.OVERTIME_INVALID,
                        'min_value': rules.OVERTIME_NEGATIVE,
                        'max_value': rules.OVERTIME_RANGE,
                        'max_digits': rules.OVERTIME_RANGE,
                        'max_decimal_places': rules.OVERTIME_INVALID},
    )


class SaveDaySerializer(serializers.Serializer):
    """`POST attendance/save-day/` payload."""

    project_id = StrictIntegerField(min_value=1)
    work_date = StrictISODateField(
        error_messages={'required': rules.WORK_DATE_REQUIRED,
                        'invalid': rules.WORK_DATE_REQUIRED},
    )
    entries = AttendanceEntrySerializer(many=True)

    def validate_entries(self, entries):
        worker_ids = [entry['worker_id'] for entry in entries]
        if len(worker_ids) != len(set(worker_ids)):
            raise serializers.ValidationError(rules.DUPLICATE_WORKER)
        return entries


class AttendanceSerializer(serializers.ModelSerializer):
    """`Attendance` (`models/attendance.dart:20-33`); server-owned fields read-only."""

    class Meta:
        model = Attendance
        fields = ('id', 'project_id', 'worker_id', 'work_date', 'status',
                  'overtime_hours', 'recorded_by', 'created_at', 'updated_at')
        read_only_fields = fields
