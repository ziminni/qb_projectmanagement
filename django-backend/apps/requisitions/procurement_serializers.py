"""Read serializers for the Phase 3 procurement wire shapes.

Keys are the Flutter models' keys (`material_request.dart`, `purchase_order.dart`,
`delivery.dart`, `site_count.dart`, …), nothing more. Three rules from the
contract shape this file:

* **Server-owned fields are read-only** — actor, status, totals, `po_no`,
  timestamps and POS metadata are never accepted from a request body.
* **Finance redaction** — `unit_price`, `total_amount` and receipt evidence are
  *omitted* (never zero-filled) unless the active role sees finances
  (`apps/users/capabilities.sees_finance`), the Phase 2 convention.
* **`receipt_photo_url`** is built from the private download route, never from
  a caller-supplied URL, so the file is only reachable through the authenticated
  scoped route (`purchase-orders/{id}/receipt/{name}`).

`qty_damaged` is part of `qty_received` and never enters inventory or costing.
"""

# Pyright runs without django-stubs/DRF stubs (untyped managers, `Meta`).
# pyright: reportIncompatibleVariableOverride=false, reportAttributeAccessIssue=false

from django.urls import reverse
from rest_framework import serializers

from ..users import capabilities
from .models import (
    Delivery,
    DeliveryItem,
    MaterialRequest,
    MaterialRequestItem,
    PurchaseOrder,
    PurchaseOrderItem,
    SiteCount,
)


def absolute(request, name, args):
    """The absolute URL for a named route (relative when there is no request)."""
    path = reverse(name, args=args)
    return request.build_absolute_uri(path) if request is not None else path


class RedactedSerializer(serializers.ModelSerializer):
    """Drops the finance-only keys for a role that does not see finances."""

    #: Keys only a finance role (owner / accountant) may receive.
    finance_only = ()

    def role(self):
        return self.context.get('role')

    def can_see_finance(self):
        return capabilities.sees_finance(self.role())

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if not self.can_see_finance():
            for key in self.finance_only:
                data.pop(key, None)
        return data


class MaterialRequestSerializer(serializers.ModelSerializer):
    class Meta:
        model = MaterialRequest
        fields = (
            'id', 'project_id', 'category_id', 'requested_by', 'needed_by',
            'status', 'approved_by', 'created_at', 'updated_at',
        )
        read_only_fields = fields


class MaterialRequestItemSerializer(serializers.ModelSerializer):
    quantity = serializers.DecimalField(
        source='quantity_requested', max_digits=12, decimal_places=2,
        read_only=True,
    )

    class Meta:
        model = MaterialRequestItem
        fields = (
            'id', 'material_request_id', 'description', 'unit', 'quantity',
            'purchase_order_id', 'created_at', 'updated_at',
        )
        read_only_fields = fields


class SiteCountSerializer(serializers.ModelSerializer):
    class Meta:
        model = SiteCount
        fields = (
            'id', 'material_request_id', 'material_id', 'name', 'unit',
            'expected', 'counted',
        )
        read_only_fields = fields


class PurchaseOrderItemSerializer(RedactedSerializer):
    finance_only = ('unit_price',)

    class Meta:
        model = PurchaseOrderItem
        fields = (
            'id', 'purchase_order_id', 'material_id', 'description', 'unit',
            'quantity', 'unit_price', 'created_at', 'updated_at',
        )
        read_only_fields = fields


class PurchaseOrderSerializer(RedactedSerializer):
    receipt_photo_url = serializers.SerializerMethodField()
    # OR evidence is finance-sensitive too (contract access section); the
    # operational roles keep the order row without it.
    finance_only = ('total_amount', 'or_number', 'receipt_photo_url')

    class Meta:
        model = PurchaseOrder
        fields = (
            'id', 'po_no', 'project_id', 'material_request_id', 'category_id',
            'supplier_id', 'store_name', 'source', 'status', 'total_amount',
            'delivery_address', 'or_number', 'receipt_photo_url', 'approved_by',
            'created_at', 'updated_at',
        )
        read_only_fields = fields

    def get_receipt_photo_url(self, order):
        if not order.receipt_file_name:
            return None
        return absolute(
            self.context.get('request'), 'purchase-order-receipt',
            [order.pk, order.receipt_file_name],
        )


class DeliverySerializer(RedactedSerializer):
    """`receipt_photo_url` is receipt evidence, so it follows the same rule."""

    receipt_photo_url = serializers.SerializerMethodField()
    finance_only = ('receipt_photo_url',)

    class Meta:
        model = Delivery
        fields = (
            'id', 'purchase_order_id', 'received_by', 'received_at',
            'receipt_photo_url', 'created_at', 'updated_at',
        )
        read_only_fields = fields

    def get_receipt_photo_url(self, delivery):
        if not delivery.receipt_file_name:
            return None
        return absolute(
            self.context.get('request'), 'delivery-receipt',
            [delivery.pk, delivery.receipt_file_name],
        )


class DeliveryItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = DeliveryItem
        fields = (
            'id', 'delivery_id', 'purchase_order_item_id', 'qty_received',
            'qty_damaged', 'created_at', 'updated_at',
        )
        read_only_fields = fields
