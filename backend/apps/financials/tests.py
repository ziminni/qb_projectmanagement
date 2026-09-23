"""Tests for budget-vs-actuals, expense logging and the utang ledger."""

from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone

from ..projects.models import Project, Site
from ..users.models import User, UserRole
from .models import (
    BudgetCategory,
    Collectible,
    CollectiblePayment,
    CollectibleStatus,
    ExpenseLog,
    ExpenseStatus,
    PaymentMethod,
    ProjectBudget,
)


class FinancialFixtures(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.site = Site.objects.create(code='SITE-800', name='Ortigas Site')
        cls.project = Project.objects.create(
            code='PRJ-800', name='Ortigas Fitout', site=cls.site,
        )
        cls.pm = User.objects.create_user(
            username='pm2', email='pm2@example.com', password='s3cret-pass-123',
            role=UserRole.PROJECT_MANAGER,
        )


class ProjectBudgetTests(FinancialFixtures):
    def setUp(self):
        self.budget = ProjectBudget.objects.create(
            project=self.project,
            category=BudgetCategory.MATERIALS,
            planned_amount=Decimal('100000.00'),
        )

    def test_actuals_count_only_approved_expenses(self):
        ExpenseLog.objects.create(
            project=self.project, budget=self.budget,
            category=BudgetCategory.MATERIALS, description='Approved rebar',
            amount=Decimal('30000.00'), status=ExpenseStatus.APPROVED,
        )
        ExpenseLog.objects.create(
            project=self.project, budget=self.budget,
            category=BudgetCategory.MATERIALS, description='Draft cement',
            amount=Decimal('99999.00'), status=ExpenseStatus.DRAFT,
        )
        ExpenseLog.objects.create(
            project=self.project, budget=self.budget,
            category=BudgetCategory.MATERIALS, description='Rejected sand',
            amount=Decimal('88888.00'), status=ExpenseStatus.REJECTED,
        )

        self.assertEqual(self.budget.actual_amount, Decimal('30000.00'))
        self.assertEqual(self.budget.variance, Decimal('70000.00'))
        self.assertFalse(self.budget.is_over_budget)

    def test_variance_goes_negative_when_over_budget(self):
        ExpenseLog.objects.create(
            project=self.project, budget=self.budget,
            category=BudgetCategory.MATERIALS, description='Steel overrun',
            amount=Decimal('130000.00'), status=ExpenseStatus.APPROVED,
        )

        self.assertEqual(self.budget.actual_amount, Decimal('130000.00'))
        self.assertEqual(self.budget.variance, Decimal('-30000.00'))
        self.assertTrue(self.budget.is_over_budget)
        self.assertEqual(self.budget.utilization_percent, Decimal('130.00'))

    def test_utilization_is_zero_when_nothing_planned(self):
        empty = ProjectBudget.objects.create(
            project=self.project,
            category=BudgetCategory.LABOR,
            planned_amount=Decimal('0.00'),
        )

        self.assertEqual(empty.utilization_percent, Decimal('0.00'))
        self.assertFalse(empty.is_over_budget)

    def test_budget_category_is_unique_per_project(self):
        with self.assertRaises(Exception):
            ProjectBudget.objects.create(
                project=self.project,
                category=BudgetCategory.MATERIALS,
                planned_amount=Decimal('1.00'),
            )

    def test_expense_auto_links_to_matching_budget_line(self):
        expense = ExpenseLog.objects.create(
            project=self.project,
            category=BudgetCategory.MATERIALS,
            description='Auto-linked cement',
            amount=Decimal('5000.00'),
        )

        self.assertEqual(expense.budget, self.budget)

    def test_expense_without_matching_budget_stays_unlinked(self):
        expense = ExpenseLog.objects.create(
            project=self.project,
            category=BudgetCategory.SUBCONTRACTOR,
            description='No budget line yet',
            amount=Decimal('5000.00'),
        )

        self.assertIsNone(expense.budget)

    def test_approve_sets_reviewer_metadata(self):
        expense = ExpenseLog.objects.create(
            project=self.project, budget=self.budget,
            category=BudgetCategory.MATERIALS, description='Fuel',
            amount=Decimal('2500.00'),
        )

        expense.approve(self.pm)

        self.assertEqual(expense.status, ExpenseStatus.APPROVED)
        self.assertEqual(expense.approved_by, self.pm)
        self.assertIsNotNone(expense.approved_at)


class CollectibleTests(FinancialFixtures):
    def make_collectible(self, amount='10000.00', **overrides):
        defaults = {
            'reference_no': 'UT-0001',
            'project': self.project,
            'debtor_name': 'Juan Dela Cruz',
            'amount': Decimal(amount),
            'recorded_by': self.pm,
        }
        defaults.update(overrides)
        return Collectible.objects.create(**defaults)

    def test_new_collectible_is_open_with_full_balance(self):
        collectible = self.make_collectible()

        self.assertEqual(collectible.status, CollectibleStatus.OPEN)
        self.assertEqual(collectible.amount_paid, Decimal('0.00'))
        self.assertEqual(collectible.balance, Decimal('10000.00'))

    def test_partial_payment_sets_partial_status_and_reduces_balance(self):
        collectible = self.make_collectible()

        CollectiblePayment.objects.create(
            collectible=collectible, amount=Decimal('4000.00'),
            method=PaymentMethod.CASH, received_by=self.pm,
        )

        collectible.refresh_from_db()
        self.assertEqual(collectible.status, CollectibleStatus.PARTIAL)
        self.assertEqual(collectible.amount_paid, Decimal('4000.00'))
        self.assertEqual(collectible.balance, Decimal('6000.00'))

    def test_full_settlement_marks_paid(self):
        collectible = self.make_collectible(amount='5000.00')

        CollectiblePayment.objects.create(
            collectible=collectible, amount=Decimal('3000.00'), received_by=self.pm,
        )
        CollectiblePayment.objects.create(
            collectible=collectible, amount=Decimal('2000.00'), received_by=self.pm,
        )

        collectible.refresh_from_db()
        self.assertEqual(collectible.status, CollectibleStatus.PAID)
        self.assertEqual(collectible.balance, Decimal('0.00'))

    def test_overdue_detected_when_due_date_passed_and_unsettled(self):
        collectible = self.make_collectible(
            due_date=timezone.localdate() - timedelta(days=5),
        )

        self.assertTrue(collectible.is_overdue)

        collectible.recompute()
        collectible.refresh_from_db()
        self.assertEqual(collectible.status, CollectibleStatus.OVERDUE)

    def test_paid_collectible_is_not_overdue(self):
        collectible = self.make_collectible(
            amount='100.00',
            due_date=timezone.localdate() - timedelta(days=5),
        )
        CollectiblePayment.objects.create(
            collectible=collectible, amount=Decimal('100.00'), received_by=self.pm,
        )

        collectible.refresh_from_db()
        self.assertFalse(collectible.is_overdue)
        self.assertEqual(collectible.status, CollectibleStatus.PAID)

    def test_written_off_status_is_preserved_by_recompute(self):
        collectible = self.make_collectible(status=CollectibleStatus.WRITTEN_OFF)

        collectible.recompute()

        self.assertEqual(collectible.status, CollectibleStatus.WRITTEN_OFF)

    def test_reference_no_is_unique(self):
        self.make_collectible()

        with self.assertRaises(Exception):
            self.make_collectible(debtor_name='Other Debtor')