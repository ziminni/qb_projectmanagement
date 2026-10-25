"""
BuildPro CPMS — construction project domain.

Covers the commercial spine of a construction engagement: the physical site,
the signed contract, the project itself, and its breakdown into phases and
milestones (the timeline).

ERD mapping:
    SITE          → apps_projects.Site
    PROJECT       → apps_projects.Project
    CONTRACT      → apps_projects.Contract
    PROJECT_PHASE → apps_projects.ProjectPhase
    MILESTONE     → apps_projects.Milestone  (timeline entries)
"""

from decimal import Decimal

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models
from django.utils import timezone


class SiteStatus(models.TextChoices):
    PLANNED = 'PLANNED', 'Planned'
    ACTIVE = 'ACTIVE', 'Active'
    ON_HOLD = 'ON_HOLD', 'On Hold'
    COMPLETED = 'COMPLETED', 'Completed'
    CLOSED = 'CLOSED', 'Closed'


class ProjectStatus(models.TextChoices):
    PLANNING = 'PLANNING', 'Planning'
    MOBILIZATION = 'MOBILIZATION', 'Mobilization'
    IN_PROGRESS = 'IN_PROGRESS', 'In Progress'
    SUSPENDED = 'SUSPENDED', 'Suspended'
    COMPLETED = 'COMPLETED', 'Completed'
    CANCELLED = 'CANCELLED', 'Cancelled'


class ContractStatus(models.TextChoices):
    DRAFT = 'DRAFT', 'Draft'
    ACTIVE = 'ACTIVE', 'Active'
    COMPLETED = 'COMPLETED', 'Completed'
    TERMINATED = 'TERMINATED', 'Terminated'


class PhaseStatus(models.TextChoices):
    NOT_STARTED = 'NOT_STARTED', 'Not Started'
    IN_PROGRESS = 'IN_PROGRESS', 'In Progress'
    BLOCKED = 'BLOCKED', 'Blocked'
    COMPLETED = 'COMPLETED', 'Completed'


class Site(models.Model):
    """A physical construction site / project location."""

    code = models.CharField(max_length=32, unique=True)
    name = models.CharField(max_length=255)
    address = models.TextField(blank=True)
    city = models.CharField(max_length=128, blank=True)
    province = models.CharField(max_length=128, blank=True)
    status = models.CharField(
        max_length=16,
        choices=SiteStatus.choices,
        default=SiteStatus.PLANNED,
        db_index=True,
    )
    notes = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('code',)
        verbose_name = 'Site'
        verbose_name_plural = 'Sites'

    def __str__(self):
        return f'{self.code} — {self.name}'


class Project(models.Model):
    """A construction project executed at a single site."""

    code = models.CharField(max_length=32, unique=True)
    name = models.CharField(max_length=255)
    site = models.ForeignKey(
        Site,
        on_delete=models.PROTECT,
        related_name='projects',
    )
    manager = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='managed_projects',
        limit_choices_to={'role': 'PROJECT_MANAGER'},
        help_text='Assigned Project Manager.',
    )
    status = models.CharField(
        max_length=16,
        choices=ProjectStatus.choices,
        default=ProjectStatus.PLANNING,
        db_index=True,
    )
    description = models.TextField(blank=True)
    start_date = models.DateField(null=True, blank=True)
    target_end_date = models.DateField(null=True, blank=True)
    actual_end_date = models.DateField(null=True, blank=True)
    budget_amount = models.DecimalField(
        max_digits=14,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
        help_text='Approved total project budget.',
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('code',)
        verbose_name = 'Project'
        verbose_name_plural = 'Projects'
        indexes = [models.Index(fields=['status', 'site'])]

    def __str__(self):
        return f'{self.code} — {self.name}'

    @property
    def is_overdue(self):
        """True when the target end date has passed without completion."""
        if self.status in (ProjectStatus.COMPLETED, ProjectStatus.CANCELLED):
            return False
        if not self.target_end_date:
            return False
        return timezone.localdate() > self.target_end_date


class Contract(models.Model):
    """The commercial agreement backing a project.

    A project may carry more than one contract over its life (original
    award plus change orders), so this is a FK rather than a OneToOne.
    """

    project = models.ForeignKey(
        Project,
        on_delete=models.CASCADE,
        related_name='contracts',
    )
    contract_no = models.CharField(max_length=64, unique=True)
    client_name = models.CharField(max_length=255)
    client_contact = models.CharField(max_length=128, blank=True)
    amount = models.DecimalField(
        max_digits=14,
        decimal_places=2,
        validators=[MinValueValidator(Decimal('0.00'))],
    )
    retention_percent = models.DecimalField(
        max_digits=5,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
        help_text='Retention withheld from progress billings (%).',
    )
    signed_date = models.DateField(null=True, blank=True)
    completion_date = models.DateField(null=True, blank=True)
    status = models.CharField(
        max_length=16,
        choices=ContractStatus.choices,
        default=ContractStatus.DRAFT,
        db_index=True,
    )
    notes = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('-signed_date', 'contract_no')
        verbose_name = 'Contract'
        verbose_name_plural = 'Contracts'

    def __str__(self):
        return f'{self.contract_no} — {self.client_name}'


class ProjectPhase(models.Model):
    """An ordered stage of a project (e.g. Siteworks, Structural, Finishing)."""

    project = models.ForeignKey(
        Project,
        on_delete=models.CASCADE,
        related_name='phases',
    )
    name = models.CharField(max_length=255)
    sequence = models.PositiveIntegerField(
        default=1,
        help_text='Display / execution order within the project.',
    )
    status = models.CharField(
        max_length=16,
        choices=PhaseStatus.choices,
        default=PhaseStatus.NOT_STARTED,
        db_index=True,
    )
    planned_start = models.DateField(null=True, blank=True)
    planned_end = models.DateField(null=True, blank=True)
    actual_start = models.DateField(null=True, blank=True)
    actual_end = models.DateField(null=True, blank=True)
    progress_percent = models.DecimalField(
        max_digits=5,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
        help_text='Physical accomplishment (%).',
    )
    notes = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('project', 'sequence')
        verbose_name = 'Project Phase'
        verbose_name_plural = 'Project Phases'
        constraints = [
            models.UniqueConstraint(
                fields=['project', 'sequence'],
                name='unique_phase_sequence_per_project',
            ),
        ]

    def __str__(self):
        return f'{self.project.code} #{self.sequence} {self.name}'


class Milestone(models.Model):
    """A dated checkpoint on the project timeline, optionally inside a phase."""

    project = models.ForeignKey(
        Project,
        on_delete=models.CASCADE,
        related_name='milestones',
    )
    phase = models.ForeignKey(
        ProjectPhase,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='milestones',
    )
    title = models.CharField(max_length=255)
    due_date = models.DateField()
    completed_date = models.DateField(null=True, blank=True)
    notes = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('due_date',)
        verbose_name = 'Milestone'
        verbose_name_plural = 'Milestones'
        indexes = [models.Index(fields=['project', 'due_date'])]

    def __str__(self):
        return f'{self.project.code} — {self.title}'

    @property
    def is_complete(self):
        return self.completed_date is not None

    @property
    def is_late(self):
        return not self.is_complete and timezone.localdate() > self.due_date