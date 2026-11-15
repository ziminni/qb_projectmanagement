"""Payroll wire shapes: periods, lines and the cash-advance payload.

Response shapes follow `flutter/lib/data/models/{payroll_period,payroll_line}
.dart` (snake_case, money as 2-dp strings, dates as `YYYY-MM-DD`), with one
deliberate extension: a line carries **one** `statutory_deductions` amount and
a `deductions_policy` flag instead of the demo's `sss`/`philhealth`/`pagibig`
columns. The statutory policy is an open owner decision, so the backend exposes
it as unconfigured rather than inventing three numbers that look compliant.

Request payloads are strict: a JSON boolean is not an integer, a non-finite
number is refused, and an out-of-scope project never reaches them (the view
answers `404` first).
"""

# Pyright here runs without django-stubs/DRF stubs.
# pyright: reportAttributeAccessIssue=false, reportIncompatibleVariableOverride=false

from rest_framework import serializers

from ..projects.rules import as_decimal
from . import payroll_rules as rules
from .models import PayrollPeriod
from .serializers import StrictIntegerField, StrictISODateField


class MoneyField(serializers.DecimalField):
    """A finite money amount; `NaN`/`Infinity`/junk become a clean `400`."""

    def to_internal_value(self, data):
        value = as_decimal(data)
        if value is None:
            self.fail('invalid')
        return super().to_internal_value(str(value))


class PayrollPeriodSerializer(serializers.ModelSerializer):
    """`PayrollPeriod` (`payroll_period.dart:18-40`); all fields server-owned."""

    class Meta:
        model = PayrollPeriod
        fields = ('id', 'project_id', 'period_start', 'period_end', 'status',
                  'created_at', 'updated_at')
        read_only_fields = fields


class CreatePeriodSerializer(serializers.Serializer):
    """`POST payroll-periods/` payload."""

    project_id = StrictIntegerField(
        min_value=1,
        error_messages={'required': rules.PERIOD_DATES,
                        'invalid': rules.PERIOD_DATES,
                        'null': rules.PERIOD_DATES},
    )
    period_start = StrictISODateField(
        error_messages={'required': rules.PERIOD_DATES,
                        'invalid': rules.PERIOD_DATES},
    )
    period_end = StrictISODateField(
        error_messages={'required': rules.PERIOD_DATES,
                        'invalid': rules.PERIOD_DATES},
    )


class CashAdvanceSerializer(serializers.Serializer):
    """`POST payroll-periods/{id}/cash-advance/` payload."""

    worker_id = StrictIntegerField(
        min_value=1,
        error_messages={'required': rules.ADVANCE_NO_ATTENDANCE,
                        'invalid': rules.ADVANCE_NO_ATTENDANCE,
                        'null': rules.ADVANCE_NO_ATTENDANCE},
    )
    amount = MoneyField(
        max_digits=12, decimal_places=2, min_value=0,
        error_messages={'required': rules.ADVANCE_INVALID,
                        'invalid': rules.ADVANCE_INVALID,
                        'min_value': rules.ADVANCE_NEGATIVE,
                        'max_digits': rules.ADVANCE_OVER_GROSS,
                        'max_decimal_places': rules.ADVANCE_INVALID},
    )


class PayrollLineSerializer(serializers.Serializer):
    """A payroll line on the wire, computed or stored (`payroll_line.dart`).

    Computed rows carry `id: 0`: the pay is derived from live attendance until
    the period is processed, and only a processed line has a stored id.
    """

    id = serializers.IntegerField()
    payroll_period_id = serializers.IntegerField()
    worker_id = serializers.IntegerField()
    days_worked = serializers.DecimalField(max_digits=5, decimal_places=2)
    overtime_pay = serializers.DecimalField(max_digits=12, decimal_places=2)
    gross_pay = serializers.DecimalField(max_digits=12, decimal_places=2)
    sss = serializers.DecimalField(max_digits=12, decimal_places=2)
    philhealth = serializers.DecimalField(max_digits=12, decimal_places=2)
    pagibig = serializers.DecimalField(max_digits=12, decimal_places=2)
    cash_advance = serializers.DecimalField(max_digits=12, decimal_places=2)
    statutory_deductions = serializers.DecimalField(
        max_digits=12, decimal_places=2,
    )
    deductions_policy = serializers.CharField()
    net_pay = serializers.DecimalField(max_digits=12, decimal_places=2)
