"""Requisition, release-token and POS-sync serializers."""

from rest_framework import serializers

from .models import (
    MaterialRequest,
    MaterialRequestItem,
    PosSyncLog,
    ReleaseToken,
)


class MaterialRequestItemSerializer(serializers.ModelSerializer):
    approved_value = serializers.DecimalField(
        max_digits=14,
        decimal_places=2,
        read_only=True,
    )
    outstanding_quantity = serializers.DecimalField(
        max_digits=12,
        decimal_places=2,
        read_only=True,
    )

    class Meta:
        model = MaterialRequestItem
        fields = (
            'id', 'material_request', 'item_sku', 'description', 'unit',
            'quantity_requested', 'quantity_approved', 'quantity_released',
            'unit_cost', 'approved_value', 'outstanding_quantity',
            'created_at', 'updated_at',
        )
        read_only_fields = ('id', 'created_at', 'updated_at')


class ReleaseTokenSerializer(serializers.ModelSerializer):
    status_display = serializers.CharField(source='get_status_display', read_only=True)
    is_redeemable = serializers.BooleanField(read_only=True)
    issued_by_name = serializers.CharField(source='issued_by.full_name', read_only=True)

    class Meta:
        model = ReleaseToken
        fields = (
            'id', 'material_request', 'token', 'status', 'status_display',
            'issued_by', 'issued_by_name', 'issued_at', 'expires_at',
            'redeemed_at', 'redeemed_by_name', 'pos_reference',
            'is_redeemable', 'notes', 'created_at', 'updated_at',
        )
        read_only_fields = (
            'id', 'token', 'issued_at', 'expires_at', 'redeemed_at',
            'created_at', 'updated_at',
        )


class MaterialRequestSerializer(serializers.ModelSerializer):
    items = MaterialRequestItemSerializer(many=True, read_only=True)
    status_display = serializers.CharField(source='get_status_display', read_only=True)
    priority_display = serializers.CharField(source='get_priority_display', read_only=True)
    project_code = serializers.CharField(source='project.code', read_only=True)
    site_code = serializers.CharField(source='site.code', read_only=True)
    requested_by_name = serializers.CharField(source='requested_by.full_name', read_only=True)
    reviewed_by_name = serializers.CharField(source='reviewed_by.full_name', read_only=True)
    total_approved_value = serializers.DecimalField(
        max_digits=14,
        decimal_places=2,
        read_only=True,
    )

    class Meta:
        model = MaterialRequest
        fields = (
            'id', 'request_no', 'project', 'project_code', 'site', 'site_code',
            'requested_by', 'requested_by_name', 'status', 'status_display',
            'priority', 'priority_display', 'needed_date', 'purpose', 'notes',
            'reviewed_by', 'reviewed_by_name', 'reviewed_at', 'rejection_reason',
            'items', 'total_approved_value', 'created_at', 'updated_at',
        )
        read_only_fields = (
            'id', 'requested_by', 'reviewed_by', 'reviewed_at',
            'rejection_reason', 'created_at', 'updated_at',
        )


class ApproveRequestSerializer(serializers.Serializer):
    """Payload for approving a requisition."""

    partial = serializers.BooleanField(default=False)


class RejectRequestSerializer(serializers.Serializer):
    """Payload for rejecting a requisition."""

    reason = serializers.CharField(required=False, allow_blank=True, default='')


class PosSyncLogSerializer(serializers.ModelSerializer):
    class Meta:
        model = PosSyncLog
        fields = (
            'id', 'material_request', 'release_token', 'endpoint', 'method',
            'status_code', 'success', 'request_payload', 'response_payload',
            'error_message', 'duration_ms', 'created_at',
        )
        read_only_fields = fields