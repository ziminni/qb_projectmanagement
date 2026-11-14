"""Master data the admin keeps: materials, suppliers, trades, equipment.

Deliberately separate from `apps.site_inventory` (which tracks serialized
assets deployed to a site): these are the price lists the desktop's Master
lists / Price lists screen edits (`master_data_repository.dart`).

ERD mapping:
    MATERIALS         → apps_master_data.MaterialItem
    SUPPLIERS         → apps_master_data.Supplier
    TRADES            → apps_master_data.Trade
    EQUIPMENT (master)→ apps_master_data.EquipmentItem
"""

# Pyright here runs without django-stubs, so model fields are inferred as their
# `Field` class (the same suppression `apps/users/models.py` uses).
# pyright: reportAttributeAccessIssue=false

from decimal import Decimal

from django.core.validators import MinValueValidator
from django.db import models
from django.db.models.functions import Lower


class EquipmentOwnership(models.TextChoices):
    """`EquipmentOwnership` in `equipment.dart`."""

    OWNED = 'owned', 'Owned'
    RENTED = 'rented', 'Rented'


class RateUnit(models.TextChoices):
    """`RateUnit` in `equipment.dart` (a day rate is billed over 8 hours)."""

    HOUR = 'hour', 'per hour'
    DAY = 'day', 'per day'


class MaterialItem(models.Model):
    """A material with its default unit cost (`material_item.dart`)."""

    name = models.CharField(max_length=200)
    unit = models.CharField(max_length=32)
    default_unit_cost = models.DecimalField(
        max_digits=12, decimal_places=2, default=Decimal('0.00'),
        validators=[MinValueValidator(0)],
    )
    store_sku = models.CharField(max_length=64, null=True, blank=True)
    # Server-side only (decision 05 §3): the POS selling-unit barcode this
    # material maps to. Not in the Flutter model; never required by the client.
    pos_code = models.CharField(max_length=64, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Material'
        verbose_name_plural = 'Materials'
        ordering = ('name', 'id')
        constraints = [
            # Names are unique case-insensitively after trimming
            # (`mock_master_data_repository.dart:29-33,110-116`).
            models.UniqueConstraint(Lower('name'), name='apps_master_data_material_name_ci_unique'),
        ]

    def __str__(self):
        return str(self.name)

    def save(self, *args, **kwargs):
        self.name = str(self.name).strip()
        super().save(*args, **kwargs)


class Supplier(models.Model):
    """A supplier; the firm's own hardware store is one with `is_own_store`."""

    name = models.CharField(max_length=200)
    contact_person = models.CharField(max_length=200, null=True, blank=True)
    phone = models.CharField(max_length=32, null=True, blank=True)
    address = models.TextField(null=True, blank=True)
    is_own_store = models.BooleanField(default=False)
    # Server-side only (decision 04): the POS customer an own-store PO bills.
    # POS validates it as an active payer-type customer id.
    pos_payer_id = models.PositiveBigIntegerField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Supplier'
        verbose_name_plural = 'Suppliers'
        ordering = ('-is_own_store', 'name', 'id')
        constraints = [
            models.UniqueConstraint(Lower('name'), name='apps_master_data_supplier_name_ci_unique'),
        ]

    def __str__(self):
        return str(self.name)

    def save(self, *args, **kwargs):
        self.name = str(self.name).strip()
        super().save(*args, **kwargs)


class Trade(models.Model):
    """A trade (Mason, Carpenter, …) used by daily-report manpower and workers."""

    name = models.CharField(max_length=200)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Trade'
        verbose_name_plural = 'Trades'
        ordering = ('name', 'id')
        constraints = [
            models.UniqueConstraint(Lower('name'), name='apps_master_data_trade_name_ci_unique'),
        ]

    def __str__(self):
        return str(self.name)

    def save(self, *args, **kwargs):
        self.name = str(self.name).strip()
        super().save(*args, **kwargs)


class EquipmentItem(models.Model):
    """A piece of equipment for costing, with its own rate (`equipment.dart`).

    Named `EquipmentItem` so it never shadows `apps.site_inventory.Equipment`,
    which tracks a serialized asset deployed to a site.
    """

    name = models.CharField(max_length=200)
    ownership = models.CharField(
        max_length=16, choices=EquipmentOwnership.choices,
        default=EquipmentOwnership.OWNED,
    )
    rate = models.DecimalField(
        max_digits=12, decimal_places=2, default=Decimal('0.00'),
        validators=[MinValueValidator(0)],
    )
    rate_unit = models.CharField(
        max_length=8, choices=RateUnit.choices, default=RateUnit.DAY,
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = 'Equipment item'
        verbose_name_plural = 'Equipment items'
        # No uniqueness on the name: the mock has none
        # (`mock_master_data_repository.dart:99-115`); see the contract's flags.
        ordering = ('name', 'id')

    def __str__(self):
        return str(self.name)

    def save(self, *args, **kwargs):
        self.name = str(self.name).strip()
        super().save(*args, **kwargs)
