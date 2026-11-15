"""
BuildPro CPMS — construction project domain (Phase 2).

Covers the client record, the project, who is on it (`ProjectAssignment`), and
the work breakdown structure (`Category` + `Todo`). Shapes mirror
`flutter/lib/data/models/{project,project_assignment,category,todo,client}.dart`
— see `planning/backend-integration/contracts/phase-2-projects-and-site.md`.

The legacy `Contract` / `ProjectPhase` / `Milestone` tables and the legacy
`Project.manager` / `budget_amount` / `description` columns are **kept but not
exposed**: the wire contract renders the Phase 2 shapes only. They are the
record of the pre-2.1 data (migration 0005 folds only the provable values into
the new columns and leaves the originals in place — see the phase 2 contract,
"Legacy data preservation"). Nothing else in the codebase reads them.

ERD mapping:
    CLIENT             → apps_projects.Client
    PROJECT            → apps_projects.Project
    PROJECT_ASSIGNMENT → apps_projects.ProjectAssignment
    CATEGORY           → apps_projects.Category
    TODO               → apps_projects.Todo

`Site` stays for now: `site_inventory` and `requisitions` still hang off it and
Phase 3 decides its fate (decision 06 #10 is about the app split, not Site).
"""

# Pyright here runs without django-stubs, so model fields and FKs are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

from decimal import Decimal

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models
from django.db.models.functions import Upper

# Default display order of a category inside its project.
DEFAULT_SEQUENCE = 1


class SiteStatus(models.TextChoices):
    PLANNED = 'PLANNED', 'Planned'
    ACTIVE = 'ACTIVE', 'Active'
    ON_HOLD = 'ON_HOLD', 'On Hold'
    COMPLETED = 'COMPLETED', 'Completed'
    CLOSED = 'CLOSED', 'Closed'


class ProjectStatus(models.TextChoices):
    """Mirror of Flutter `ProjectStatus`; `DECLINED` is DB-only (decision 06 R1)."""

    REQUESTED = 'requested', 'Waiting for client'
    CHANGES_REQUESTED = 'changes_requested', 'Changes requested'
    SITE_ENGINEER_PENDING = 'site_engineer_pending', 'Waiting for site engineer'
    ACCEPTED = 'accepted', 'Accepted'
    ONGOING = 'ongoing', 'Ongoing'
    COMPLETED = 'completed', 'Completed'
    CLOSED = 'closed', 'Closed'
    ON_HOLD = 'on_hold', 'On hold'
    # Never serialized: a declined project is hidden from every read.
    DECLINED = 'declined', 'Declined'


class RoleOnProject(models.TextChoices):
    """Mirror of Flutter `AppRole` restricted to roles that join a project."""

    OWNER = 'owner', 'Owner / Project manager'
    SITE_ENGINEER = 'site_engineer', 'Site engineer / foreman'
    CLIENT = 'client', 'Client'


class RequestResponse(models.TextChoices):
    """Mirror of Flutter `RequestResponse`."""

    NOT_SENT = 'not_sent', 'Sent after the client accepts'
    PENDING = 'pending', 'Waiting for reply'
    ACCEPTED = 'accepted', 'Accepted'
    CHANGES_REQUESTED = 'changes_requested', 'Asked for changes'
    DECLINED = 'declined', 'Declined'


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


class Client(models.Model):
    """A client company the firm builds for (`models/client.dart`).

    `user` is the portal login linked to this client record, if one exists yet.
    """

    name = models.CharField(max_length=255)
    contact_person = models.CharField(max_length=255, blank=True)
    email = models.EmailField(blank=True)
    phone = models.CharField(max_length=32, blank=True)
    address = models.TextField(blank=True)
    # One portal login belongs to one client record at most.
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='client_record',
        help_text='The portal login linked to this client, when there is one.',
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('name', 'id')
        verbose_name = 'Client'
        verbose_name_plural = 'Clients'

    def __str__(self):
        return self.name


class Project(models.Model):
    """A construction project, shaped for the Flutter desktop client.

    `start_date` / `target_end_date` / `client` / `location` stay nullable at
    the database level because `financials`, `requisitions` and `site_inventory`
    create projects in their own fixtures; the API requires them on create.
    """

    code = models.CharField(max_length=32, unique=True)
    name = models.CharField(max_length=255)
    location = models.CharField(max_length=255, blank=True)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    client = models.ForeignKey(
        Client,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name='projects',
    )
    contract_amount = models.DecimalField(
        max_digits=14,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
    )
    down_payment_pct = models.DecimalField(
        max_digits=5,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
        help_text='Down payment billed on the contract (%).',
    )
    retention_pct = models.DecimalField(
        max_digits=5,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
        help_text='Retention withheld from progress billings (%).',
    )
    start_date = models.DateField(null=True, blank=True)
    target_end_date = models.DateField(null=True, blank=True)
    actual_end_date = models.DateField(null=True, blank=True)
    status = models.CharField(
        max_length=32,
        choices=ProjectStatus.choices,
        default=ProjectStatus.REQUESTED,
        db_index=True,
    )
    # --- legacy columns, kept so no pre-2.1 record is lost (review 2.1) -------
    # Not serialized. `legacy_status` carries the pre-2.1 status code verbatim;
    # migration 0005 maps it onto `status` and writes nothing else here.
    legacy_status = models.CharField(
        max_length=16,
        blank=True,
        default='',
        help_text='Project status before Phase 2, kept for reconciliation.',
    )
    description = models.TextField(blank=True)
    budget_amount = models.DecimalField(
        max_digits=14,
        decimal_places=2,
        default=Decimal('0.00'),
        validators=[MinValueValidator(Decimal('0.00'))],
        help_text='Approved total project budget.',
    )
    manager = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='managed_projects',
        limit_choices_to={'user_roles__role': 'owner'},
        help_text='Assigned Project Manager.',
    )
    # Legacy link for the Phase 3 apps; Flutter sends location/lat/long instead.
    site = models.ForeignKey(
        Site,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name='projects',
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('code',)
        verbose_name = 'Project'
        verbose_name_plural = 'Projects'
        indexes = [models.Index(fields=['status'])]
        constraints = [
            # The API upper-cases the code before saving; this keeps a stray
            # lower-case row from being created twice by a script.
            models.UniqueConstraint(Upper('code'), name='apps_projects_code_ci_unique'),
        ]

    def __str__(self):
        return f'{self.code} — {self.name}'


class ProjectAssignment(models.Model):
    """A user's membership of one project in one role.

    Only `response = accepted` grants project scope; every other value hides the
    project from that user (they still see the request under `project-requests/`).
    """

    project = models.ForeignKey(
        Project,
        on_delete=models.CASCADE,
        related_name='assignments',
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='project_assignments',
    )
    role_on_project = models.CharField(max_length=16, choices=RoleOnProject.choices)
    response = models.CharField(
        max_length=20,
        choices=RequestResponse.choices,
        default=RequestResponse.PENDING,
        db_index=True,
    )
    note = models.TextField(blank=True, null=True, help_text='Why it was declined.')
    responded_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('project', 'role_on_project', 'user')
        verbose_name = 'Project assignment'
        verbose_name_plural = 'Project assignments'
        constraints = [
            models.UniqueConstraint(
                fields=['project', 'user', 'role_on_project'],
                name='unique_assignment_per_project_user_role',
            ),
        ]

    def __str__(self):
        return f'{self.role_on_project} on project {self.project_id} (user {self.user_id})'

    @property
    def is_active(self):
        """True only when this assignment grants scope."""
        return self.response == RequestResponse.ACCEPTED


class Category(models.Model):
    """A budgeted slice of the work breakdown (`models/category.dart`)."""

    project = models.ForeignKey(
        Project,
        on_delete=models.CASCADE,
        related_name='categories',
    )
    name = models.CharField(max_length=255)
    budget = models.DecimalField(
        max_digits=14,
        decimal_places=2,
        null=True,
        blank=True,
        validators=[MinValueValidator(Decimal('0.00'))],
        help_text='Planned spend; finance-only, and drives the progress weight.',
    )
    sort_order = models.PositiveIntegerField(default=DEFAULT_SEQUENCE)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('sort_order', 'id')
        verbose_name = 'Category'
        verbose_name_plural = 'Categories'

    def __str__(self):
        return f'{self.name} ({self.project_id})'


class Todo(models.Model):
    """A checkable item inside a category; only verified to-dos count (`models/todo.dart`)."""

    category = models.ForeignKey(
        Category,
        on_delete=models.CASCADE,
        related_name='todos',
    )
    title = models.CharField(max_length=255)
    start_date = models.DateField()
    end_date = models.DateField()
    is_done = models.BooleanField(default=False)
    done_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='todos_done',
    )
    done_at = models.DateTimeField(null=True, blank=True)
    is_verified = models.BooleanField(default=False)
    verified_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='todos_verified',
    )
    verified_at = models.DateTimeField(null=True, blank=True)
    # The daily report this to-do was accomplished on (`models/todo.dart`).
    # Migration 0006 turns the 2.1 integer into this real FK; any value that
    # pointed at no report moved to `legacy_daily_report_id` instead of being
    # dropped (see the phase 2 contract, "Legacy data preservation").
    daily_report = models.ForeignKey(
        'apps_site_reports.DailyReport',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='todos',
    )
    legacy_daily_report_id = models.BigIntegerField(
        null=True,
        blank=True,
        help_text='Pre-2.2 report id that matched no report; kept, not exposed.',
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ('start_date', 'id')
        verbose_name = 'To-do'
        verbose_name_plural = 'To-dos'

    def __str__(self):
        return self.title


# ---------------------------------------------------------------------------
# Legacy Phase 1 tables — kept, unexposed
# ---------------------------------------------------------------------------
# The Phase 2 API has no route for these. They stay because dropping them would
# destroy the only copy of real contract/phase/milestone history (review 2.1
# blocker); migration 0005 copies the unambiguous values forward and leaves
# every row untouched.

class Contract(models.Model):
    """Pre-2.1 contract record; `Project.contract_amount` is the new home."""

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
        choices=[
            ('DRAFT', 'Draft'), ('ACTIVE', 'Active'),
            ('COMPLETED', 'Completed'), ('TERMINATED', 'Terminated'),
        ],
        default='DRAFT',
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
    """Pre-2.1 timeline phase; `Category` is the new home (decision 05)."""

    project = models.ForeignKey(
        Project,
        on_delete=models.CASCADE,
        related_name='phases',
    )
    name = models.CharField(max_length=255)
    sequence = models.PositiveIntegerField(
        default=1, help_text='Display / execution order within the project.',
    )
    status = models.CharField(
        max_length=16,
        choices=[
            ('NOT_STARTED', 'Not Started'), ('IN_PROGRESS', 'In Progress'),
            ('BLOCKED', 'Blocked'), ('COMPLETED', 'Completed'),
        ],
        default='NOT_STARTED',
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
        return f'{self.sequence}. {self.name}'


class Milestone(models.Model):
    """Pre-2.1 milestone; a `Todo` has no provable equivalent, so it is kept."""

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
        indexes = [
            models.Index(
                fields=['project', 'due_date'],
                name='apps_projec_project_78e505_idx',
            ),
        ]

    def __str__(self):
        return self.title
