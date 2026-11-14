"""Fold the provable legacy values forward; destroy nothing (review 2.1).

Migration 0004 stopped dropping the pre-2.1 tables and columns, so this one can
copy instead of recreate:

* every `Project` row keeps its original status code in `legacy_status`;
* `status` moves to the Phase 2 code set, one-to-one where the meaning is the
  same (`IN_PROGRESS`→`ongoing`, `SUSPENDED`→`on_hold`, `COMPLETED`→`completed`,
  `CANCELLED`→`closed`) and collapsed where Phase 2 has fewer pre-work states
  (`PLANNING`/`MOBILIZATION`→`accepted`);
* a project with **exactly one** `Contract` gets its `amount`/`retention_percent`
  copied into `contract_amount`/`retention_pct` and a `Client` record from the
  contract's `client_name`/`client_contact`;
* the legacy `manager` becomes an accepted `owner` assignment, so the project
  has scope in the Phase 2 API;
* a project with several contracts keeps `0.00` in the new columns and no
  client: which contract is "the" contract is not provable, so the conflict
  stays in the `Contract` rows and is reported in the phase 2 contract rather
  than guessed. `budget_amount` → `Category.budget` and phase/milestone →
  Category/Todo are **not** derived either: the destination needs a value the
  source does not have (a category name, a to-do start date).

Reversing is a no-op: the folded values stay, the originals were never touched.
"""

from django.db import migrations, models
from django.utils import timezone

# Legacy upper-case code -> Phase 2 status.
LEGACY_STATUS_MAP = {
    'PLANNING': 'accepted',
    'MOBILIZATION': 'accepted',
    'IN_PROGRESS': 'ongoing',
    'SUSPENDED': 'on_hold',
    'COMPLETED': 'completed',
    'CANCELLED': 'closed',
}

# The Phase 2 codes; a row already holding one is left alone (idempotent).
PHASE2_STATUSES = {
    'requested', 'changes_requested', 'site_engineer_pending', 'accepted',
    'ongoing', 'completed', 'closed', 'on_hold', 'declined',
}

ZERO = 0


def fold_legacy_data(apps, schema_editor):
    Project = apps.get_model('apps_projects', 'Project')
    Contract = apps.get_model('apps_projects', 'Contract')
    Client = apps.get_model('apps_projects', 'Client')
    ProjectAssignment = apps.get_model('apps_projects', 'ProjectAssignment')

    for project in Project.objects.all().order_by('pk'):
        _remap_status(project)
        contracts = list(
            Contract.objects.filter(project_id=project.pk).order_by('pk')
        )
        if len(contracts) == 1:
            _fold_contract(project, contracts[0], Client)
        _fold_manager(project, ProjectAssignment)


def _remap_status(project):
    """Keep the old code verbatim, then move `status` onto a Phase 2 code."""
    previous = project.status
    if not project.legacy_status:
        project.legacy_status = previous
    if previous not in PHASE2_STATUSES:
        # A code known to neither set cannot be left in place: `status` is a
        # Phase 2 choice field and Flutter parses it strictly. `requested` is
        # the neutral "not started" entry point, and `legacy_status` still
        # carries the original verbatim.
        project.status = LEGACY_STATUS_MAP.get(previous, 'requested')
    project.save(update_fields=['status', 'legacy_status'])


def _fold_contract(project, contract, Client):
    """Copy the single contract's terms and client; keep the contract row."""
    copied = []
    if project.contract_amount == ZERO:
        project.contract_amount = contract.amount
        copied.append('contract_amount')
    if project.retention_pct == ZERO:
        project.retention_pct = contract.retention_percent
        copied.append('retention_pct')
    if project.client_id is None:
        client, created = Client.objects.get_or_create(name=contract.client_name)
        if not client.contact_person and contract.client_contact:
            client.contact_person = contract.client_contact
            client.save(update_fields=['contact_person'])
        elif created:
            pass
        project.client_id = client.pk
        copied.append('client')
    if copied:
        project.save(update_fields=copied)


def _fold_manager(project, ProjectAssignment):
    """The legacy manager becomes the project's accepted owner."""
    if project.manager_id is None:
        return
    exists = ProjectAssignment.objects.filter(
        project_id=project.pk,
        user_id=project.manager_id,
        role_on_project='owner',
    ).exists()
    if exists:
        return
    ProjectAssignment.objects.create(
        project_id=project.pk,
        user_id=project.manager_id,
        role_on_project='owner',
        response='accepted',
        responded_at=timezone.now(),
    )


class Migration(migrations.Migration):

    dependencies = [
        ('apps_projects', '0004_category_client_projectassignment_todo_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='project',
            name='legacy_status',
            field=models.CharField(
                blank=True,
                default='',
                help_text='Project status before Phase 2, kept for reconciliation.',
                max_length=16,
            ),
        ),
        migrations.RunPython(fold_legacy_data, migrations.RunPython.noop),
    ]
