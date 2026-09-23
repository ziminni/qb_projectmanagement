"""
BuildPro CPMS — site-level inventory and equipment tracking.

Tracks what physically sits at each construction site: consumable stock,
small tools held in quantity, and serialized heavy equipment with its
deployment history.

ERD mapping:
    SITE_STOCK      → apps_site_inventory.SiteStock
    TOOL            → apps_site_inventory.Tool
    EQUIPMENT       → apps_site_inventory.Equipment
    EQUIPMENT_LOG   → apps_site_inventory.EquipmentLog
"""

from decimal import Decimal

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models
from django.utils import timezone

from ..projects.models import Site


class StockCondition(models.TextChoices):
    GOOD = 'GOOD', 'Good'
    DAMAGED = 'DAMAGED', 'Damaged'
    CONSUMED = 'CONSUMED', 'Consumed'


class EquipmentStatus(models.TextChoices):
    AVAILABLE = 'AVAILABLE', 'Available'
    IN_USE = 'IN_USE', 'In Use'
    MAINTENANCE = 'MAINTENANCE', 'Under Maintenance'
    BREAKDOWN = 'BREAKDOWN', 'Breakdown'
    RETIRED = 'RETIRED', 'Retired'


class EquipmentEvent(models.TextChoices):
    DEPLOY = 'DEPLOY', 'Deployed to Site'
    RETURN = 'RETURN', 'Returned to Yard'
    TRANSFER = 'TRANSFER', 'Transferred Between Sites'
    MAINTENANCE = 'MAINTENANCE', 'Sent for Maintenance'
    BREAKDOWN = 'BREAKDOWN', 'Reported Breakdown'
    REPAIR = 'REPAIR', 'Repair Completed'


class SiteStock(models.Model):
    """Consumable material currently on hand at a site.

    Mirrors POS item SKUs so requisitions can be reconciled against the
    hardware store's catalogue.
    """

    site = models.ForeignKey(
        Site,
        on_delete=models.CASCADE,
        related_name='stock_items',
    )
    item_sku = models.CharField(
        max_length=64,
        help_text='SKU from the POS catalogue (Repo #1).',
    )
    item_name = models.CharField(max_length=255)
    unit = models.CharField(max_length=32, default='pc')
    quantity_on_hand = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
    )
    reorder_level = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
    )
    unit_cost = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
    )
    condition = models.CharField(
        max_length=16,
        choices=StockCondition.choices,
        default=StockCondition.GOOD,
    )
    last_counted_at = models.DateTimeField(null=True, blank=True)
    notes = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('site', 'item_name')
        verbose_name = 'Site Stock'
        verbose_name_plural = 'Site Stock'
        constraints = [
            models.UniqueConstraint(
                fields=['site', 'item_sku'],
                name='unique_sku_per_site',
            ),
        ]

    def __str__(self):
        return f'{self.site.code} / {self.item_sku} ({self.quantity_on_hand} {self.unit})'

    @property
    def is_below_reorder_level(self):
        return self.quantity_on_hand <= self.reorder_level

    @property
    def total_value(self):
        return self.quantity_on_hand * self.unit_cost


class Tool(models.Model):
    """Small tools held in quantity at a site (non-serialized)."""

    site = models.ForeignKey(
        Site,
        on_delete=models.CASCADE,
        related_name='tools',
    )
    code = models.CharField(max_length=64)
    name = models.CharField(max_length=255)
    category = models.CharField(max_length=128, blank=True)
    quantity_total = models.PositiveIntegerField(default=1)
    quantity_available = models.PositiveIntegerField(default=1)
    condition = models.CharField(
        max_length=16,
        choices=StockCondition.choices,
        default=StockCondition.GOOD,
    )
    custodian = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='custodian_tools',
        help_text='Person accountable for these tools on site.',
    )
    notes = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('site', 'name')
        verbose_name = 'Tool'
        verbose_name_plural = 'Tools'
        constraints = [
            models.UniqueConstraint(
                fields=['site', 'code'],
                name='unique_tool_code_per_site',
            ),
            models.CheckConstraint(
                condition=models.Q(quantity_available__lte=models.F('quantity_total')),
                name='tool_available_lte_total',
            ),
        ]

    def __str__(self):
        return f'{self.site.code} / {self.code} — {self.name}'

    @property
    def quantity_deployed(self):
        return self.quantity_total - self.quantity_available


class Equipment(models.Model):
    """Serialized heavy equipment / machinery, tracked per site."""

    asset_code = models.CharField(max_length=64, unique=True)
    name = models.CharField(max_length=255)
    category = models.CharField(max_length=128, blank=True)
    site = models.ForeignKey(
        Site,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='equipment',
        help_text='Current site assignment (null when in the yard).',
    )
    status = models.CharField(
        max_length=16,
        choices=EquipmentStatus.choices,
        default=EquipmentStatus.AVAILABLE,
        db_index=True,
    )
    operator = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='operated_equipment',
    )
    acquired_date = models.DateField(null=True, blank=True)
    maintenance_due = models.DateField(null=True, blank=True)
    hourly_rate = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
        help_text='Internal charging rate for budget vs actuals.',
    )
    notes = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('asset_code',)
        verbose_name = 'Equipment'
        verbose_name_plural = 'Equipment'
        indexes = [models.Index(fields=['status', 'site'])]

    def __str__(self):
        return f'{self.asset_code} — {self.name}'

    @property
    def is_maintenance_overdue(self):
        if not self.maintenance_due:
            return False
        return timezone.localdate() > self.maintenance_due


class EquipmentLog(models.Model):
    """Append-only movement / status history for a piece of equipment."""

    equipment = models.ForeignKey(
        Equipment,
        on_delete=models.CASCADE,
        related_name='logs',
    )
    event_type = models.CharField(max_length=16, choices=EquipmentEvent.choices)
    site = models.ForeignKey(
        Site,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='equipment_logs',
    )
    note = models.TextField(blank=True)
    logged_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='equipment_logs',
    )
    occurred_at = models.DateTimeField(default=timezone.now)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ('-occurred_at',)
        verbose_name = 'Equipment Log'
        verbose_name_plural = 'Equipment Logs'

    def __str__(self):
        return f'{self.equipment.asset_code} — {self.get_event_type_display()}'