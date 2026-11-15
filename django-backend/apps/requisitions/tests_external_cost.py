"""`projects/{id}/external-materials-cost/`: outside-store materials cost by category.

Owner decision 2026-11-15: the store's charged total is the own-store materials cost
and is read from the store, so this route counts **external** purchases only. Counting
an own-store delivery here as well would count the same goods twice.
"""

from decimal import Decimal

from rest_framework.test import APITestCase

from ..projects.models import Category
from ..users.models import Role
from .models import Delivery, DeliveryItem, MaterialSource, PurchaseOrder, PurchaseOrderItem
from .tests_procurement import ProcurementFixtures


def url(project_id):
    return f'/api/v1/projects/{project_id}/external-materials-cost/'


class ExternalMaterialsCostTests(ProcurementFixtures, APITestCase):
    def order(self, project, category, source, price, qty='10.00'):
        order = PurchaseOrder.objects.create(
            project=project, category=category, source=source,
            store_name='Downtown Hardware' if source == MaterialSource.EXTERNAL else '',
        )
        line = PurchaseOrderItem.objects.create(
            purchase_order=order, material=self.cement, description='Cement',
            unit='bag', quantity=Decimal(qty), unit_price=Decimal(price),
        )
        return line

    def deliver(self, line, received, damaged='0.00'):
        delivery = Delivery.objects.create(
            purchase_order=line.purchase_order, received_by=self.engineer,
        )
        DeliveryItem.objects.create(
            delivery=delivery, purchase_order_item=line,
            qty_received=Decimal(received), qty_damaged=Decimal(damaged),
        )

    def test_counts_undamaged_received_external_goods_by_category(self):
        roofing = Category.objects.create(project=self.project, name='Roofing', sort_order=2)
        line = self.order(self.project, self.category, MaterialSource.EXTERNAL, '260.00')
        self.deliver(line, '6.00', damaged='1.00')
        self.deliver(line, '4.00')
        self.deliver(self.order(self.project, roofing, MaterialSource.EXTERNAL, '99.50', '3'), '2.00')

        self.act_as(self.accountant, Role.ACCOUNTANT)
        response = self.client.get(url(self.project.pk))

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data, {
            'project_id': self.project.pk,
            'by_category': {str(self.category.pk): '2340.00', str(roofing.pk): '199.00'},
        })

    def test_own_store_goods_are_left_to_the_store_figure(self):
        self.deliver(self.order(self.project, self.category, MaterialSource.OWN_STORE, '260.00'), '10.00')

        self.act_as(self.owner, Role.OWNER)
        response = self.client.get(url(self.project.pk))

        self.assertEqual(response.data['by_category'], {})

    def test_other_projects_and_ordered_but_undelivered_goods_do_not_count(self):
        self.order(self.project, self.category, MaterialSource.EXTERNAL, '260.00')
        self.deliver(
            self.order(self.other_project, self.other_category, MaterialSource.EXTERNAL, '1.00'),
            '5.00',
        )

        self.act_as(self.owner, Role.OWNER)
        self.assertEqual(self.client.get(url(self.project.pk)).data['by_category'], {})

    def test_only_finance_roles_in_scope(self):
        self.act_as(self.engineer, Role.SITE_ENGINEER)
        self.assertEqual(self.client.get(url(self.project.pk)).status_code, 403)
        self.act_as(self.owner, Role.OWNER)
        self.assertEqual(self.client.get(url(self.other_project.pk)).status_code, 404)
