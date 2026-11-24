"""Site inventory serializers."""

from rest_framework import serializers

from ..users.models import Role
from .models import (
    Equipment,
    EquipmentBorrowSource,
    EquipmentLog,
    ProjectEquipmentBorrow,
    SiteStock,
    Tool,
)


class SiteStockSerializer(serializers.ModelSerializer):
    site_code = serializers.CharField(source='site.code', read_only=True)
    is_below_reorder_level = serializers.BooleanField(read_only=True)
    total_value = serializers.DecimalField(
        max_digits=14,
        decimal_places=2,
        read_only=True,
    )

    class Meta:
        model = SiteStock
        fields = (
            'id', 'site', 'site_code', 'item_sku', 'item_name', 'unit',
            'quantity_on_hand', 'reorder_level', 'unit_cost', 'condition',
            'is_below_reorder_level', 'total_value', 'last_counted_at',
            'notes', 'created_at', 'updated_at',
        )
        read_only_fields = ('id', 'created_at', 'updated_at')


class ToolSerializer(serializers.ModelSerializer):
    site_code = serializers.CharField(source='site.code', read_only=True)
    custodian_name = serializers.CharField(source='custodian.full_name', read_only=True)
    quantity_deployed = serializers.IntegerField(read_only=True)

    class Meta:
        model = Tool
        fields = (
            'id', 'site', 'site_code', 'code', 'name', 'category',
            'quantity_total', 'quantity_available', 'quantity_deployed',
            'condition', 'custodian', 'custodian_name', 'notes',
            'created_at', 'updated_at',
        )
        read_only_fields = ('id', 'created_at', 'updated_at')

    def validate(self, attrs):
        total = attrs.get('quantity_total', getattr(self.instance, 'quantity_total', 0))
        available = attrs.get(
            'quantity_available',
            getattr(self.instance, 'quantity_available', 0),
        )
        if available is not None and total is not None and available > total:
            raise serializers.ValidationError(
                {'quantity_available': 'Available quantity cannot exceed total quantity.'}
            )
        return attrs


class EquipmentSerializer(serializers.ModelSerializer):
    site_name = serializers.CharField(source='site.name', read_only=True)
    operator_name = serializers.CharField(source='operator.full_name', read_only=True)
    is_maintenance_overdue = serializers.BooleanField(read_only=True)

    class Meta:
        model = Equipment
        fields = (
            'id', 'asset_code', 'name', 'category', 'site', 'site_name',
            'status', 'operator', 'operator_name', 'acquired_date',
            'maintenance_due', 'is_maintenance_overdue', 'hourly_rate',
            'notes', 'created_at', 'updated_at',
        )
        read_only_fields = ('id', 'created_at', 'updated_at')


class EquipmentLogSerializer(serializers.ModelSerializer):
    equipment_code = serializers.CharField(source='equipment.asset_code', read_only=True)
    logged_by_name = serializers.CharField(source='logged_by.full_name', read_only=True)

    class Meta:
        model = EquipmentLog
        fields = (
            'id', 'equipment', 'equipment_code', 'event_type', 'site',
            'note', 'logged_by', 'logged_by_name', 'occurred_at', 'created_at',
        )
        read_only_fields = ('id', 'created_at')


class ProjectEquipmentBorrowSerializer(serializers.ModelSerializer):
    category_name = serializers.CharField(source='category.name', read_only=True)
    borrower_trade = serializers.CharField(
        source='borrower_worker.trade.name', read_only=True, default=None,
    )
    requested_by_name = serializers.CharField(
        source='requested_by.full_name', read_only=True,
    )
    reviewed_by_name = serializers.CharField(
        source='reviewed_by.full_name', read_only=True, default=None,
    )
    returned_by_name = serializers.CharField(
        source='returned_by.full_name', read_only=True, default=None,
    )

    class Meta:
        model = ProjectEquipmentBorrow
        fields = (
            'id',
            'project_id',
            'category_id',
            'category_name',
            'equipment_item_id',
            'source',
            'equipment_name',
            'quantity',
            'borrower_worker_id',
            'borrower_name',
            'borrower_trade',
            'rental_supplier',
            'rental_rate',
            'rate_unit',
            'needed_date',
            'expected_return_date',
            'status',
            'return_condition',
            'return_notes',
            'returned_at',
            'returned_by_id',
            'returned_by_name',
            'requested_by_id',
            'requested_by_name',
            'reviewed_by_id',
            'reviewed_by_name',
            'rejection_reason',
            'notes',
            'created_at',
            'updated_at',
        )
        read_only_fields = fields

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if self.context.get('role') == Role.SITE_ENGINEER:
            data['rental_rate'] = None
        return data


class ProjectEquipmentBorrowCreateSerializer(serializers.Serializer):
    project_id = serializers.IntegerField()
    category_id = serializers.IntegerField(required=False, allow_null=True)
    equipment_item_id = serializers.IntegerField(required=False, allow_null=True)
    source = serializers.ChoiceField(
        choices=EquipmentBorrowSource.choices,
        default=EquipmentBorrowSource.OWNED,
    )
    equipment_name = serializers.CharField(
        max_length=200, required=False, allow_blank=True,
    )
    quantity = serializers.IntegerField(min_value=1, max_value=999, default=1)
    borrower_worker_id = serializers.IntegerField(required=False, allow_null=True)
    borrower_name = serializers.CharField(
        max_length=200, required=False, allow_blank=True, default='',
    )
    rental_supplier = serializers.CharField(
        max_length=200, required=False, allow_blank=True, default='',
    )
    rental_rate = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False, allow_null=True,
    )
    rate_unit = serializers.ChoiceField(
        choices=[('day', 'day'), ('hour', 'hour')],
        default='day',
    )
    needed_date = serializers.DateField()
    expected_return_date = serializers.DateField(required=False, allow_null=True)
    notes = serializers.CharField(required=False, allow_blank=True, default='')

    def validate(self, attrs):
        needed = attrs.get('needed_date')
        ret = attrs.get('expected_return_date')
        if needed and ret and ret < needed:
            raise serializers.ValidationError(
                'Expected return date cannot be earlier than the needed date.'
            )
        return attrs
