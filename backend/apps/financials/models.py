"""
BuildPro CPMS — project financials and the utang/collectibles ledger.

Covers budget-versus-actuals per cost category, the project expense log,
and money owed to the firm by project clients (utang), reconciled against
the POS collectibles ledger.

ERD mapping:
    PROJECT_BUDGET     → apps_financials.ProjectBudget
    EXPENSE_LOG        → apps_financials.ExpenseLog
    COLLECTIBLE        → apps_financials.Collectible   (utang)
    COLLECTIBLE_PAYMENT → apps_financials.CollectiblePayment
"""

from decimal import Decimal

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models
from django.utils import timezone

from ..projects.models import Project


class BudgetCategory(models.TextChoices):
    MATERIALS = 'MATERIALS', 'Materials'
    LABOR = 'LABOR', 'Labor'
    EQUIPMENT = 'EQUIPMENT', 'Equipment & Rental'
    SUBCONTRACTOR = 'SUBCONTRACTOR', 'Subcontractor'
    OVERHEAD = 'OVERHEAD', 'Overhead & Admin'
    OTHER = 'OTHER', 'Other'


class ExpenseStatus(models.TextChoices):
    DRAFT = 'DRAFT', 'Draft'
    SUBMITTED = 'SUBMITTED', 'Submitted'
    APPROVED = 'APPROVED', 'Approved'
    REJECTED = 'REJECTED', 'Rejected'


class CollectibleStatus(models.TextChoices):
    OPEN = 'OPEN', 'Open'
    PARTIAL = 'PARTIAL', 'Partially Paid'
    PAID = 'PAID', 'Paid'
    OVERDUE = 'OVERDUE', 'Overdue'
    WRITTEN_OFF = 'WRITTEN_OFF', 'Written Off'


class PaymentMethod(models.TextChoices):
    CASH = 'CASH', 'Cash'
    BANK = 'BANK', 'Bank Transfer'
    CHECK = 'CHECK', 'Check'
    GCASH = 'GCASH', 'E-Wallet'
    MATERIAL_OFFSET = 'MATERIAL_OFFSET', 'Material Offset'


class ProjectBudget(models.Model):
    """Planned spend for one cost category of a project.

    Actuals are derived from approved ExpenseLog rows sharing the same
    project and category, so the two never drift out of sync.
    """

    project = models.ForeignKey(
        Project,
        on_delete=models.CASCADE,
        related_name='budgets',
    )
    category = models.CharField(max_length=16, choices=BudgetCategory.choices)
    planned_amount = models.DecimalField(
        max_digits=14,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
    )
    notes = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('project', 'category')
        verbose_name = 'Project Budget'
        verbose_name_plural = 'Project Budgets'
        constraints = [
            models.UniqueConstraint(
                fields=['project', 'category'],
                name='unique_budget_category_per_project',
            ),
        ]

    def __str__(self):
        return f'{self.project.code} / {self.get_category_display()}'

    @property
    def actual_amount(self):
        """Approved spend booked against this budget line.

        Draft, submitted and rejected expenses are deliberately excluded so
        that budget-versus-actuals reflects committed cost only.
        """
        return self.expenses.filter(status=ExpenseStatus.APPROVED).aggregate(
            total=models.Sum('amount')
        )['total'] or Decimal('0.00')

    @property
    def variance(self):
        """Positive means under budget, negative means overspent."""
        return self.planned_amount - self.actual_amount

    @property
    def utilization_percent(self):
        if not self.planned_amount:
            return Decimal('0.00')
        return (self.actual_amount / self.planned_amount) * 100

    @property
    def is_over_budget(self):
        return self.actual_amount > self.planned_amount


class ExpenseLog(models.Model):
    """A single incurred project expense."""

    project = models.ForeignKey(
        Project,
        on_delete=models.PROTECT,
        related_name='expenses',
    )
    # Anchored to the matching ProjectBudget line; null when no budget exists
    # yet for this category (the expense is still recorded and visible).
    budget = models.ForeignKey(
        ProjectBudget,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='expenses',
    )
    category = models.CharField(max_length=16, choices=BudgetCategory.choices)
    description = models.CharField(max_length=255)
    amount = models.DecimalField(
        max_digits=14,
        decimal_places=2,
        validators=[MinValueValidator(Decimal('0.01'))],
    )
    incurred_on = models.DateField(default=timezone.localdate)
    receipt_no = models.CharField(max_length=64, blank=True)
    supplier = models.CharField(max_length=255, blank=True)

    status = models.CharField(
        max_length=16,
        choices=ExpenseStatus.choices,
        default=ExpenseStatus.DRAFT,
        db_index=True,
    )
    recorded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='recorded_expenses',
    )
    approved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='approved_expenses',
    )
    approved_at = models.DateTimeField(null=True, blank=True)
    notes = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('-incurred_on', '-id')
        verbose_name = 'Expense Log'
        verbose_name_plural = 'Expense Logs'
        indexes = [
            models.Index(fields=['project', 'category']),
            models.Index(fields=['status', 'incurred_on']),
        ]

    def __str__(self):
        return f'{self.project.code} — {self.description} ({self.amount})'

    def save(self, *args, **kwargs):
        """Auto-link to the project's budget line for this category."""
        if self.budget_id is None and self.project_id and self.category:
            self.budget = ProjectBudget.objects.filter(
                project_id=self.project_id,
                category=self.category,
            ).first()
        super().save(*args, **kwargs)

    def approve(self, user):
        self.status = ExpenseStatus.APPROVED
        self.approved_by = user
        self.approved_at = timezone.now()
        self.save(update_fields=['status', 'approved_by', 'approved_at', 'updated_at'])


class Collectible(models.Model):
    """Money owed to the firm — "utang" — usually a client or project account.

    `amount_paid` is a cached rollup of CollectiblePayment rows, refreshed
    via recompute() whenever a payment is recorded.
    """

    reference_no = models.CharField(max_length=64, unique=True)
    project = models.ForeignKey(
        Project,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='collectibles',
    )
    debtor_name = models.CharField(max_length=255)
    debtor_contact = models.CharField(max_length=128, blank=True)
    description = models.TextField(blank=True)
    amount = models.DecimalField(
        max_digits=14,
        decimal_places=2,
        validators=[MinValueValidator(Decimal('0.01'))],
    )
    amount_paid = models.DecimalField(
        max_digits=14,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
        help_text='Cached sum of recorded payments; call recompute() after changes.',
    )
    due_date = models.DateField(null=True, blank=True)
    status = models.CharField(
        max_length=16,
        choices=CollectibleStatus.choices,
        default=CollectibleStatus.OPEN,
        db_index=True,
    )
    pos_collectible_ref = models.CharField(
        max_length=64,
        blank=True,
        help_text='Matching collectible reference in the POS ledger.',
    )
    recorded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='recorded_collectibles',
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('-created_at',)
        verbose_name = 'Collectible'
        verbose_name_plural = 'Collectibles (Utang)'
        indexes = [models.Index(fields=['status', 'due_date'])]

    def __str__(self):
        return f'{self.reference_no} — {self.debtor_name} ({self.balance})'

    @property
    def balance(self):
        return self.amount - self.amount_paid

    @property
    def is_overdue(self):
        if self.status in (CollectibleStatus.PAID, CollectibleStatus.WRITTEN_OFF):
            return False
        if not self.due_date:
            return False
        return timezone.localdate() > self.due_date

    def recompute(self, save=True):
        """Refresh the cached paid total and derive the ledger status."""
        paid = self.payments.aggregate(total=models.Sum('amount'))['total'] or Decimal('0.00')
        self.amount_paid = paid

        if self.status == CollectibleStatus.WRITTEN_OFF:
            pass
        elif paid >= self.amount:
            self.status = CollectibleStatus.PAID
        elif self.is_overdue:
            self.status = CollectibleStatus.OVERDUE
        elif paid > 0:
            self.status = CollectibleStatus.PARTIAL
        else:
            self.status = CollectibleStatus.OPEN

        if save:
            self.save(update_fields=['amount_paid', 'status', 'updated_at'])
        return self.amount_paid


class CollectiblePayment(models.Model):
    """A payment applied against a Collectible (utang)."""

    collectible = models.ForeignKey(
        Collectible,
        on_delete=models.CASCADE,
        related_name='payments',
    )
    amount = models.DecimalField(
        max_digits=14,
        decimal_places=2,
        validators=[MinValueValidator(Decimal('0.01'))],
    )
    paid_on = models.DateField(default=timezone.localdate)
    method = models.CharField(
        max_length=16,
        choices=PaymentMethod.choices,
        default=PaymentMethod.CASH,
    )
    reference_no = models.CharField(max_length=64, blank=True)
    received_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='received_payments',
    )
    notes = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ('-paid_on', '-id')
        verbose_name = 'Collectible Payment'
        verbose_name_plural = 'Collectible Payments'

    def __str__(self):
        return f'{self.collectible.reference_no} — {self.amount}'

    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        # Keep the parent's cached rollup and status in step with its payments.
        self.collectible.recompute()