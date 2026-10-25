"""Tests for site stock, tools and equipment tracking."""

from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone

from ..projects.models import Site
from .models import Equipment, EquipmentStatus, SiteStock, StockCondition, Tool


class SiteStockTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.site = Site.objects.create(code='SITE-500', name='Cebu Plant')

    def test_reorder_level_breach_is_detected(self):
        low = SiteStock.objects.create(
            site=self.site, item_sku='CEM-40KG', item_name='Cement 40kg',
            quantity_on_hand=Decimal('5'), reorder_level=Decimal('20'),
        )
        healthy = SiteStock.objects.create(
            site=self.site, item_sku='SND-1M', item_name='Sand 1m3',
            quantity_on_hand=Decimal('50'), reorder_level=Decimal('20'),
        )

        self.assertTrue(low.is_below_reorder_level)
        self.assertFalse(healthy.is_below_reorder_level)

    def test_total_value_multiplies_quantity_by_unit_cost(self):
        stock = SiteStock.objects.create(
            site=self.site, item_sku='STL-10MM', item_name='Rebar 10mm',
            quantity_on_hand=Decimal('100'),
            unit_cost=Decimal('185.50'),
        )

        self.assertEqual(stock.total_value, Decimal('18550.00'))

    def test_sku_is_unique_per_site_but_shared_across_sites(self):
        other_site = Site.objects.create(code='SITE-501', name='Davao Plant')
        SiteStock.objects.create(
            site=self.site, item_sku='CEM-40KG', item_name='Cement 40kg',
        )

        # Same SKU at a different site is legitimate.
        SiteStock.objects.create(
            site=other_site, item_sku='CEM-40KG', item_name='Cement 40kg',
        )
        self.assertEqual(SiteStock.objects.filter(item_sku='CEM-40KG').count(), 2)

        # Same SKU at the same site is not.
        with self.assertRaises(Exception):
            SiteStock.objects.create(
                site=self.site, item_sku='CEM-40KG', item_name='Duplicate',
            )


class ToolTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.site = Site.objects.create(code='SITE-600', name='Baguio Site')

    def test_quantity_deployed_is_derived(self):
        tool = Tool.objects.create(
            site=self.site, code='TL-001', name='Angle Grinder',
            quantity_total=10, quantity_available=4,
        )

        self.assertEqual(tool.quantity_deployed, 6)

    def test_available_cannot_exceed_total(self):
        with self.assertRaises(Exception):
            Tool.objects.create(
                site=self.site, code='TL-002', name='Impact Drill',
                quantity_total=2, quantity_available=5,
            )

    def test_tool_code_unique_per_site(self):
        Tool.objects.create(
            site=self.site, code='TL-003', name='Chainsaw',
            quantity_total=1, quantity_available=1,
            condition=StockCondition.GOOD,
        )

        with self.assertRaises(Exception):
            Tool.objects.create(
                site=self.site, code='TL-003', name='Chainsaw Duplicate',
                quantity_total=1, quantity_available=1,
            )


class EquipmentTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.site = Site.objects.create(code='SITE-700', name='Laguna Site')

    def test_maintenance_overdue_flag(self):
        overdue = Equipment.objects.create(
            asset_code='EQ-001', name='Backhoe', site=self.site,
            maintenance_due=timezone.localdate() - timedelta(days=2),
        )
        upcoming = Equipment.objects.create(
            asset_code='EQ-002', name='Concrete Mixer', site=self.site,
            maintenance_due=timezone.localdate() + timedelta(days=30),
        )
        undated = Equipment.objects.create(
            asset_code='EQ-003', name='Generator', site=self.site,
        )

        self.assertTrue(overdue.is_maintenance_overdue)
        self.assertFalse(upcoming.is_maintenance_overdue)
        self.assertFalse(undated.is_maintenance_overdue)

    def test_equipment_can_be_unassigned_from_a_site(self):
        equipment = Equipment.objects.create(asset_code='EQ-010', name='Crane')

        self.assertIsNone(equipment.site)
        self.assertEqual(equipment.status, EquipmentStatus.AVAILABLE)
        self.assertEqual(str(equipment), 'EQ-010 — Crane')