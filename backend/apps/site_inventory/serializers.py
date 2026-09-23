"""Site inventory serializers."""

from rest_framework import serializers

from .models import Equipment, EquipmentLog, SiteStock, Tool


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