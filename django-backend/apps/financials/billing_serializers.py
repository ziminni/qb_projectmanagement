"""Billing serializers: wire shapes and the write payloads.

Response shapes follow `flutter/lib/data/models/{progress_billing,payment,
variation_order,retention_release}.dart` (snake_case, money as 2-dp strings,
dates as `YYYY-MM-DD`). Request payloads are deliberately strict: a JSON
boolean is not an integer, a non-finite number is refused, and an out-of-scope
project never reaches these serializers (the view answers `404` first).

The client portal gets the same billing money — it is the bill — but it never
gets a route to retention summaries or another project's rows (see the contract
"Permissions and delegated defaults").
"""

# Pyright here runs without django-stubs/DRF stubs.
# pyright: reportAttributeAccessIssue=false, reportIncompatibleVariableOverride=false

from datetime import date
from decimal import Decimal

from rest_framework import serializers

from ..projects.rules import as_decimal
from ..users.serializers import AuditLogSerializer
from . import billing_rules as rules
from .models import (
    ClientPayment,
    ClientPaymentMethod,
    ProgressBilling,
    RetentionRelease,
    VariationOrder,
    VariationOrderType,
)

ISO_DATE_LENGTH = 10


class StrictISODateField(serializers.DateField):
    """`YYYY-MM-DD` only: `2026-3-2` and `20260302` are refusals, not guesses."""

    def to_internal_value(self, data):
        if not isinstance(data, str) or len(data) != ISO_DATE_LENGTH:
            self.fail('invalid')
        try:
            return date.fromisoformat(data)
        except ValueError:
            self.fail('invalid')


class StrictIntegerField(serializers.IntegerField):
    """An integer that refuses JSON booleans (`true` is not `1`)."""

    def to_internal_value(self, data):
        if isinstance(data, bool):
            self.fail('invalid')
        return super().to_internal_value(data)


class MoneyField(serializers.DecimalField):
    """A finite money amount; `NaN`/`Infinity`/junk become a clean `400`."""

    def to_internal_value(self, data):
        value = as_decimal(data)
        if value is None:
            self.fail('invalid')
        return super().to_internal_value(str(value))


class ProgressBillingSerializer(serializers.ModelSerializer):
    """`ProgressBilling` (`progress_billing.dart:33-63`)."""

    this_period = serializers.SerializerMethodField()

    class Meta:
        model = ProgressBilling
        fields = (
            'id', 'project_id', 'billing_no', 'period_end', 'pct_accomplished',
            'gross_earned', 'less_previous', 'less_dp_recoupment',
            'less_retention', 'net_due', 'this_period', 'status',
            'created_at', 'updated_at',
        )
        read_only_fields = fields

    def get_this_period(self, billing):
        return f'{billing.this_period:.2f}'


class ProgressBillingDetailSerializer(ProgressBillingSerializer):
    """One billing with its payments and its audit history (`BillingDetail`)."""

    payments = serializers.SerializerMethodField()
    history = serializers.SerializerMethodField()

    class Meta(ProgressBillingSerializer.Meta):
        fields = ProgressBillingSerializer.Meta.fields + ('payments', 'history')

    def get_payments(self, billing):
        rows = billing.payments.order_by('-paid_on', '-id')
        return ClientPaymentSerializer(rows, many=True).data

    def get_history(self, billing):
        from . import billing_services

        return AuditLogSerializer(
            billing_services.history('progress_billing', billing.pk), many=True,
        ).data


class ClientPaymentSerializer(serializers.ModelSerializer):
    """`Payment` (`payment.dart:6-30`); every field is server-owned."""

    class Meta:
        model = ClientPayment
        fields = ('id', 'progress_billing_id', 'amount', 'paid_on', 'method',
                  'reference_no', 'created_at', 'updated_at')
        read_only_fields = fields


class VariationOrderSerializer(serializers.ModelSerializer):
    """`VariationOrder` (`variation_order.dart:43-72`)."""

    approved_by_owner = serializers.IntegerField(
        source='approved_by_owner_id', read_only=True, allow_null=True,
    )
    approved_by_client = serializers.IntegerField(
        source='approved_by_client_id', read_only=True, allow_null=True,
    )

    class Meta:
        model = VariationOrder
        fields = (
            'id', 'project_id', 'vo_no', 'type', 'description', 'amount',
            'days_impact', 'primary_attachments', 'secondary_attachments',
            'status', 'approved_by_owner', 'approved_by_client',
            'created_at', 'updated_at',
        )
        read_only_fields = fields


class VariationOrderDetailSerializer(VariationOrderSerializer):
    """One VO with its audit history (`VariationOrderDetail`)."""

    history = serializers.SerializerMethodField()

    class Meta(VariationOrderSerializer.Meta):
        fields = VariationOrderSerializer.Meta.fields + ('history',)

    def get_history(self, order):
        from . import billing_services

        return AuditLogSerializer(
            billing_services.history('variation_order', order.pk), many=True,
        ).data


class RetentionReleaseSerializer(serializers.ModelSerializer):
    """`RetentionRelease` (`retention_release.dart:8-33`)."""

    class Meta:
        model = RetentionRelease
        fields = ('id', 'project_id', 'amount', 'released_on', 'method',
                  'reference_no', 'created_at', 'updated_at')
        read_only_fields = fields


class BillingFiguresSerializer(serializers.Serializer):
    """The computed figures of one billing (preview, or the row just created)."""

    pct_accomplished = serializers.DecimalField(
        max_digits=7, decimal_places=6, read_only=True,
    )
    gross_earned = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True)
    less_previous = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True)
    less_dp_recoupment = serializers.DecimalField(
        max_digits=14, decimal_places=2, read_only=True,
    )
    less_retention = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True)
    this_period = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True)
    net_due = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True)


class CreateBillingSerializer(serializers.Serializer):
    """`POST progress-billings/` — the client never sends a number."""

    project_id = StrictIntegerField(min_value=1)
    period_end = StrictISODateField(
        error_messages={'required': rules.PERIOD_REQUIRED,
                        'invalid': rules.PERIOD_REQUIRED},
    )


class RecordPaymentSerializer(serializers.Serializer):
    """`POST progress-billings/{id}/payments/`."""

    amount = MoneyField(
        max_digits=14, decimal_places=2,
        error_messages={'required': rules.PAYMENT_POSITIVE,
                        'invalid': rules.PAYMENT_POSITIVE,
                        'max_digits': rules.PAYMENT_INVALID,
                        'max_decimal_places': rules.PAYMENT_INVALID},
    )
    paid_on = StrictISODateField(required=False)
    method = serializers.ChoiceField(
        choices=ClientPaymentMethod.choices,
        error_messages={'invalid_choice': rules.METHOD_INVALID},
    )
    reference_no = serializers.CharField(
        max_length=64, required=False, allow_blank=True,
    )

    def validate_amount(self, value):
        if value <= 0:
            raise serializers.ValidationError(rules.PAYMENT_POSITIVE)
        return value

    def validate_paid_on(self, value):
        if value > date.today():
            raise serializers.ValidationError(rules.PAYMENT_DATE_FUTURE)
        return value


class ReasonSerializer(serializers.Serializer):
    """`{reason}` for a dispute or a rejection."""

    reason = serializers.CharField(
        allow_blank=True, max_length=255, trim_whitespace=True,
    )


class VariationOrderWriteSerializer(serializers.Serializer):
    """`POST variation-orders/` and `PATCH variation-orders/{id}/`."""

    project_id = StrictIntegerField(min_value=1, required=False)
    type = serializers.ChoiceField(
        choices=VariationOrderType.choices,
        error_messages={'invalid_choice': rules.VO_TYPE_INVALID},
    )
    description = serializers.CharField(
        max_length=255,
        error_messages={'required': rules.VO_DESCRIPTION,
                        'blank': rules.VO_DESCRIPTION},
    )
    amount = MoneyField(
        max_digits=14, decimal_places=2, required=False, default=Decimal('0.00'),
        error_messages={'invalid': rules.VO_AMOUNT_INVALID,
                        'max_digits': rules.VO_AMOUNT_INVALID,
                        'max_decimal_places': rules.VO_AMOUNT_INVALID},
    )
    days_impact = StrictIntegerField(
        required=False, default=0, min_value=-3650, max_value=3650,
        error_messages={'invalid': rules.VO_DAYS_INVALID,
                        'min_value': rules.VO_DAYS_INVALID,
                        'max_value': rules.VO_DAYS_INVALID},
    )
    primary_attachments = serializers.ListField(
        child=serializers.CharField(max_length=1024),
        required=False,
        default=list,
    )
    secondary_attachments = serializers.ListField(
        child=serializers.CharField(max_length=1024),
        required=False,
        default=list,
    )


class CreateRetentionReleaseSerializer(serializers.Serializer):
    """`POST retention-releases/`."""

    project_id = StrictIntegerField(min_value=1)
    amount = MoneyField(
        max_digits=14, decimal_places=2,
        error_messages={'required': rules.PAYMENT_POSITIVE,
                        'invalid': rules.PAYMENT_POSITIVE,
                        'max_digits': rules.PAYMENT_INVALID,
                        'max_decimal_places': rules.PAYMENT_INVALID},
    )
    released_on = StrictISODateField(
        error_messages={'required': rules.RELEASE_DATE_REQUIRED,
                        'invalid': rules.RELEASE_DATE_REQUIRED},
    )
    method = serializers.ChoiceField(
        choices=ClientPaymentMethod.choices,
        error_messages={'invalid_choice': rules.METHOD_INVALID},
    )
    reference_no = serializers.CharField(
        max_length=64, required=False, allow_blank=True,
    )

    def validate_amount(self, value):
        if value <= 0:
            raise serializers.ValidationError(rules.PAYMENT_POSITIVE)
        return value
