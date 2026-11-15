"""Master-data serializers (materials, suppliers, trades, equipment).

Shapes mirror `flutter/lib/data/models/*.dart`; refusal messages are the mock's,
verbatim (`mock_master_data_repository.dart`, `services/master_data_rules.dart`).

Finance redaction: `default_unit_cost` and `rate` are zeroed for an active role
without `seesFinance` (owner, accountant). They are **zeroed, not omitted** —
the Flutter models parse them with the non-null `JsonUtils.toDouble`
(`material_item.dart:47`, `equipment.dart:74`), which throws on a missing key.
"""

# Pyright here runs without django-stubs/DRF stubs: `Meta` reads as an override
# of ModelSerializer.Meta, and the mixin's `super()` / `self.context` are untyped.
# pyright: reportIncompatibleVariableOverride=false, reportOptionalMemberAccess=false, reportAttributeAccessIssue=false

from rest_framework import serializers

from ..users import capabilities
from .models import EquipmentItem, MaterialItem, Supplier, Trade


class FinanceRedactionMixin:
    """Zero `redacted_fields` for a non-finance active role, and never write them."""

    redacted_fields = ()

    def sees_finance(self):
        request = self.context.get('request')
        if request is None or not request.user.is_authenticated:
            return False
        return capabilities.sees_finance(capabilities.active_role(request))

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if not self.sees_finance():
            for field in self.redacted_fields:
                data[field] = 0
        return data

    def validate(self, attrs):
        attrs = super().validate(attrs)
        if not self.sees_finance():
            # A role that cannot see a price cannot change it either: the
            # desktop re-sends the value it loaded, so keeping the stored one
            # is exactly what the dialogs expect.
            for field in self.redacted_fields:
                attrs.pop(field, None)
        return attrs


class MaterialItemSerializer(FinanceRedactionMixin, serializers.ModelSerializer):
    """`MaterialItem` (`models/material_item.dart:40-51`)."""

    redacted_fields = ('default_unit_cost',)
    # Also returned when the unique index, not this check, refuses a duplicate.
    duplicate_name_message = 'A material with this name already exists.'

    name = serializers.CharField(
        max_length=200,
        error_messages={'required': 'Enter the material name.',
                        'blank': 'Enter the material name.'},
    )
    unit = serializers.CharField(
        max_length=32,
        error_messages={'required': 'Enter the unit.', 'blank': 'Enter the unit.'},
    )
    default_unit_cost = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False, min_value=0,
        error_messages={'invalid': 'Enter the unit cost.',
                        'min_value': 'The unit cost cannot be negative.',
                        'max_digits': 'The unit cost is too large.',
                        'max_decimal_places': 'Use at most 2 decimal places.'},
    )
    store_sku = serializers.CharField(
        max_length=64, allow_null=True, allow_blank=True, required=False,
    )
    pos_code = serializers.CharField(
        max_length=64, allow_null=True, allow_blank=True, required=False,
    )

    class Meta:
        model = MaterialItem
        fields = ('id', 'name', 'unit', 'default_unit_cost', 'store_sku',
                  'pos_code', 'created_at', 'updated_at')
        read_only_fields = ('id', 'created_at', 'updated_at')

    def validate_name(self, value):
        name = value.strip()
        if not name:
            raise serializers.ValidationError('Enter the material name.')
        others = MaterialItem.objects.filter(name__iexact=name)
        if self.instance is not None:
            others = others.exclude(pk=self.instance.pk)
        if others.exists():
            raise serializers.ValidationError(self.duplicate_name_message)
        return name

    def validate_unit(self, value):
        return value.strip()

    def validate_store_sku(self, value):
        return (value or '').strip() or None

    def validate_pos_code(self, value):
        return (value or '').strip() or None

    def validate(self, attrs):
        attrs = super().validate(attrs)
        if (self.instance is None and self.sees_finance()
                and 'default_unit_cost' not in attrs):
            raise serializers.ValidationError(
                {'default_unit_cost': 'Enter the unit cost.'})
        return attrs


class SupplierSerializer(serializers.ModelSerializer):
    """`Supplier` (`models/supplier.dart:48-60`)."""

    duplicate_name_message = 'A supplier with this name already exists.'

    name = serializers.CharField(
        max_length=200,
        error_messages={'required': 'Enter the supplier name.',
                        'blank': 'Enter the supplier name.'},
    )
    contact_person = serializers.CharField(
        max_length=200, allow_null=True, allow_blank=True, required=False,
    )
    phone = serializers.CharField(
        max_length=32, allow_null=True, allow_blank=True, required=False,
    )
    address = serializers.CharField(
        allow_null=True, allow_blank=True, required=False,
    )
    pos_payer_id = serializers.IntegerField(
        allow_null=True, min_value=1, max_value=9223372036854775807,
        required=False,
    )

    class Meta:
        model = Supplier
        fields = ('id', 'name', 'contact_person', 'phone', 'address',
                  'is_own_store', 'pos_payer_id', 'created_at', 'updated_at')
        read_only_fields = ('id', 'created_at', 'updated_at')

    def validate_name(self, value):
        name = value.strip()
        if not name:
            raise serializers.ValidationError('Enter the supplier name.')
        others = Supplier.objects.filter(name__iexact=name)
        if self.instance is not None:
            others = others.exclude(pk=self.instance.pk)
        if others.exists():
            raise serializers.ValidationError(self.duplicate_name_message)
        return name

    def validate_contact_person(self, value):
        return (value or '').strip() or None

    def validate_phone(self, value):
        return (value or '').strip() or None

    def validate_address(self, value):
        return (value or '').strip() or None


class TradeSerializer(serializers.ModelSerializer):
    """`Trade` (`models/trade.dart:18-24`)."""

    duplicate_name_message = 'This trade is already listed.'

    name = serializers.CharField(
        max_length=200,
        error_messages={'required': 'Enter the trade name.',
                        'blank': 'Enter the trade name.'},
    )

    class Meta:
        model = Trade
        fields = ('id', 'name', 'created_at', 'updated_at')
        read_only_fields = ('id', 'created_at', 'updated_at')

    def validate_name(self, value):
        name = value.strip()
        if not name:
            raise serializers.ValidationError('Enter the trade name.')
        others = Trade.objects.filter(name__iexact=name)
        if self.instance is not None:
            others = others.exclude(pk=self.instance.pk)
        if others.exists():
            raise serializers.ValidationError(self.duplicate_name_message)
        return name


class EquipmentItemSerializer(FinanceRedactionMixin, serializers.ModelSerializer):
    """`Equipment` (`models/equipment.dart:65-82`)."""

    redacted_fields = ('rate',)

    name = serializers.CharField(
        max_length=200,
        error_messages={'required': 'Enter the equipment name.',
                        'blank': 'Enter the equipment name.'},
    )
    rate = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False, min_value=0,
        error_messages={'invalid': 'Enter the rate.',
                        'min_value': 'The rate cannot be negative.',
                        'max_digits': 'The rate is too large.',
                        'max_decimal_places': 'Use at most 2 decimal places.'},
    )

    class Meta:
        model = EquipmentItem
        fields = ('id', 'name', 'ownership', 'rate', 'rate_unit',
                  'created_at', 'updated_at')
        read_only_fields = ('id', 'created_at', 'updated_at')

    def validate_name(self, value):
        name = value.strip()
        if not name:
            raise serializers.ValidationError('Enter the equipment name.')
        return name

    def validate(self, attrs):
        attrs = super().validate(attrs)
        if (self.instance is None and self.sees_finance()
                and 'rate' not in attrs):
            raise serializers.ValidationError({'rate': 'Enter the rate.'})
        return attrs


def refusal(serializer):
    """Collapse DRF field errors into the contract's single `detail` string."""
    for messages in serializer.errors.values():
        first = messages[0] if isinstance(messages, list) else messages
        if isinstance(first, dict):
            first = next(iter(first.values()))[0]
        return {'detail': str(first)}
    return {'detail': 'This change was refused.'}
