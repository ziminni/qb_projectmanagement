"""Transactional project operations: rules, audit rows and notifications.

Everything that changes a project, its team or its WBS happens here, inside
`transaction.atomic()`, so the audit row, the notification and the state change
either all land or none do. Views only pick the queryset, check the role, and
call one of these.

Rule texts come from `rules.py`; recipient sets are always **accepted**
assignments (R8).
"""

# Pyright here runs without django-stubs, so model managers/FKs are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportOptionalMemberAccess=false

import re
from typing import NoReturn

from django.db import IntegrityError, transaction
from django.utils import timezone

from ..users import capabilities
from ..users.models import Role, User
from ..users.services import notify, record
from . import rules, scoping
from .models import (
    Category,
    Client,
    Project,
    ProjectAssignment,
    ProjectStatus,
    RequestResponse,
    RoleOnProject,
    Todo,
)
from .rules import NotAllowed, RuleRefused, as_decimal, peso

CLIENT_PROJECTS_LINK = '/client/projects'      # AppRoutes.clientProjects
PROJECTS_LINK = '/projects'                    # AppRoutes.projects
TODO_VERIFICATION_LINK = '/todo-verification'  # AppRoutes.todoVerification

REQUEST_LINKS = {
    RoleOnProject.CLIENT: CLIENT_PROJECTS_LINK,
    RoleOnProject.SITE_ENGINEER: PROJECTS_LINK,
    RoleOnProject.OWNER: PROJECTS_LINK,
}


def project_link(project):
    """AppRoutes.projectTab(project, overview)."""
    return f'{PROJECTS_LINK}/{project.pk}/overview'


def _text(value):
    return '' if value is None else str(value).strip()


def _date(value):
    """Parse a `yyyy-MM-dd` string (or a date) into a date, or None."""
    if value in (None, ''):
        return None
    if hasattr(value, 'year') and hasattr(value, 'month'):
        return value
    try:
        from datetime import date

        return date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def _refuse(message) -> NoReturn:
    raise RuleRefused(message)


# Unique index names that back a rule. A race past the pre-check lands here.
CODE_CONSTRAINTS = (
    'apps_projects_project_code_key',   # Project.code unique
    'apps_projects_code_ci_unique',     # Upper(code) unique
)
ASSIGNMENT_CONSTRAINT = 'unique_assignment_per_project_user_role'


def _is_unique_violation(error, *names):
    """True only for the expected unique indexes (anything else must surface)."""
    message = str(error)
    return any(name in message for name in names)


def _code_taken(code, exclude_pk=None):
    """The check-then-insert pre-check for `Project.code` (case-insensitive)."""
    queryset = Project.objects.filter(code__iexact=code)
    if exclude_pk is not None:
        queryset = queryset.exclude(pk=exclude_pk)
    return queryset.exists()


def _assignment_exists(project, user, role_on_project):
    """The check-then-insert pre-check for a live assignment row."""
    return project.assignments.filter(
        user=user, role_on_project=role_on_project,
    ).exists()


# --------------------------------------------------------------------------
# Notifications
# --------------------------------------------------------------------------

def notify_project_role(project, role_on_project, message, type='project_request', link=None):
    """Notify every **accepted** member of the project in `role_on_project`."""
    member_ids = dict.fromkeys(
        project.assignments.filter(
            role_on_project=role_on_project,
            response=RequestResponse.ACCEPTED,
        ).values_list('user_id', flat=True)
    )
    for member in User.objects.filter(pk__in=member_ids):
        notify(member, type, message, link=link)


def notify_owners(project, message, link=None, type='project_request'):
    notify_project_role(
        project, RoleOnProject.OWNER, message, type=type,
        link=link if link is not None else project_link(project),
    )


def send_request(assignment):
    """Send the `project_request` notification for a row waiting on an answer."""
    if assignment.response != RequestResponse.PENDING:
        return
    project = assignment.project
    is_client = assignment.role_on_project == RoleOnProject.CLIENT
    message = (
        f'New project request: {project.code} {project.name}. '
        'Accept it, ask for changes or decline it.'
        if is_client
        else f'New project request: {project.code} {project.name}. Accept or decline it.'
    )
    notify(
        assignment.user, 'project_request', message,
        link=REQUEST_LINKS[assignment.role_on_project],
    )


# --------------------------------------------------------------------------
# Projects
# --------------------------------------------------------------------------

def _validate_project_fields(values):
    """Refuse on the first broken project rule, in the mock's order."""
    if not _text(values.get('code')):
        _refuse('Enter the project code.')
    if not _text(values.get('name')):
        _refuse('Enter the project name.')
    message = rules.validate_contract_amount(values.get('contract_amount'))
    if message:
        _refuse(message)
    message = rules.validate_dates(
        _date(values.get('start_date')), _date(values.get('target_end_date')),
    )
    if message:
        _refuse(message)
    message = rules.validate_percent(values.get('down_payment_pct'), 'down payment')
    if message:
        _refuse(message)
    message = rules.validate_percent(values.get('retention_pct'), 'retention')
    if message:
        _refuse(message)
    client = values.get('client')
    if client is None:
        _refuse('Choose the client.')
    if client.user_id is None:
        _refuse('This client has no app login yet. Ask the admin to create one.')


def _clean_project_values(payload, project=None):
    """Merge the payload over the current row into the values the rules check."""
    values = {
        'code': project.code if project else None,
        'name': project.name if project else None,
        'contract_amount': project.contract_amount if project else None,
        'start_date': project.start_date if project else None,
        'target_end_date': project.target_end_date if project else None,
        'down_payment_pct': project.down_payment_pct if project else None,
        'retention_pct': project.retention_pct if project else None,
        'client': project.client if project else None,
    }
    if 'code' in payload:
        values['code'] = _text(payload.get('code')).upper()
    if 'name' in payload:
        values['name'] = _text(payload.get('name'))
    for field in ('contract_amount', 'down_payment_pct', 'retention_pct'):
        if field in payload:
            values[field] = as_decimal(payload.get(field))
    for field in ('start_date', 'target_end_date'):
        if field in payload:
            values[field] = _date(payload.get(field))
    if 'client_id' in payload:
        client_id = payload.get('client_id')
        values['client'] = (
            Client.objects.filter(pk=client_id).first() if client_id else None
        )
    return values


def _apply_project_values(project, values):
    """Copy validated values onto the row; dates/decimals already parsed."""
    project.code = values['code']
    project.name = values['name']
    project.contract_amount = values['contract_amount']
    project.down_payment_pct = values['down_payment_pct']
    project.retention_pct = values['retention_pct']
    project.start_date = values['start_date']
    project.target_end_date = values['target_end_date']
    project.client = values['client']


def _save_project(project):
    """Save a project, turning a lost code race into the mock's refusal.

    The inner atomic block is the savepoint: without it a caught
    `IntegrityError` would poison the enclosing transaction. Only the two code
    indexes are expected; any other `IntegrityError` is re-raised.
    """
    try:
        with transaction.atomic():
            project.save()
    except IntegrityError as error:
        if not _is_unique_violation(error, *CODE_CONSTRAINTS):
            raise
        _refuse('Another project already uses this code.')


@transaction.atomic
def create_project(actor, active_role, payload):
    """Create a project, its creator's owner assignment and the audit row."""
    if active_role != RoleOnProject.OWNER:
        raise NotAllowed('Only a project manager can create a project.')

    values = _clean_project_values(payload)
    _validate_project_fields(values)
    if _code_taken(values['code']):
        _refuse('Another project already uses this code.')

    project = Project(status=ProjectStatus.REQUESTED)
    _apply_project_values(project, values)
    project.location = _text(payload.get('location'))
    project.latitude = as_decimal(payload.get('latitude'))
    project.longitude = as_decimal(payload.get('longitude'))
    _save_project(project)

    ProjectAssignment.objects.create(
        project=project,
        user=actor,
        role_on_project=RoleOnProject.OWNER,
        response=RequestResponse.ACCEPTED,
        responded_at=timezone.now(),
    )
    record(actor, 'project_created', 'project', project.pk, {'code': project.code})
    return project


@transaction.atomic
def update_project(actor, active_role, project, payload):
    """Owner edits; the contract amount and the client may be frozen."""
    if active_role != RoleOnProject.OWNER:
        raise NotAllowed('Only the owner running this project can edit it.')
    scoping.require_owner(
        project, actor, 'Only the owner running this project can edit it.',
    )

    values = _clean_project_values(payload, project)
    _validate_project_fields(values)
    if _code_taken(values['code'], exclude_pk=project.pk):
        _refuse('Another project already uses this code.')

    amount_changed = values['contract_amount'] != project.contract_amount
    if (
        amount_changed
        and payload.get('contract_amount') is not None
        and project.status in rules.WORK_STARTED_STATUSES
    ):
        _refuse(
            'Once work starts the contract amount changes only through approved '
            'variation orders.'
        )
    client_changed = values['client'] != project.client
    if (
        client_changed
        and payload.get('client_id') is not None
        and project.status in rules.CLIENT_LOCKED_STATUSES
    ):
        _refuse('The client cannot be changed once the client has accepted the project.')

    changed = []
    for field, value in (
        ('code', values['code']),
        ('name', values['name']),
        ('contract_amount', values['contract_amount']),
        ('down_payment_pct', values['down_payment_pct']),
        ('retention_pct', values['retention_pct']),
        ('start_date', values['start_date']),
        ('target_end_date', values['target_end_date']),
        ('client', values['client']),
    ):
        if getattr(project, field) != value:
            changed.append(field)
    _apply_project_values(project, values)
    for field in ('location', 'latitude', 'longitude'):
        if field in payload:
            value = payload.get(field)
            value = as_decimal(value) if field != 'location' else _text(value)
            if getattr(project, field) != value:
                changed.append(field)
                setattr(project, field, value)
    _save_project(project)
    record(actor, 'project_updated', 'project', project.pk, {'fields': changed})
    return project


@transaction.atomic
def change_status(actor, active_role, project, raw_status):
    """Owner moves the project through its manual transitions."""
    if raw_status not in ProjectStatus.values or raw_status == ProjectStatus.DECLINED:
        _refuse('Choose a valid status.')
    target = ProjectStatus(raw_status)
    if active_role != RoleOnProject.OWNER:
        raise NotAllowed(f'Only the owner can move a project to {target.label}.')
    scoping.require_owner(
        project, actor, f'Only the owner can move a project to {target.label}.',
    )
    previous = ProjectStatus(project.status)
    if target not in rules.NEXT_STATUSES.get(previous, []):
        _refuse(
            f'A project cannot move from {previous.label} to {target.label}.'
        )

    project.status = target
    if target == ProjectStatus.COMPLETED:
        project.actual_end_date = timezone.localdate()
    project.save(update_fields=['status', 'actual_end_date', 'updated_at'])

    record(
        actor, 'project_status_changed', 'project', project.pk,
        {'from': previous.value, 'to': target.value},
    )
    message = f'{project.code} {project.name} is now {target.label}.'
    others = User.objects.filter(
        pk__in=project.assignments.filter(
            response=RequestResponse.ACCEPTED,
        ).exclude(user_id=actor.pk).values_list('user_id', flat=True),
    )
    for member in others:
        notify(member, 'project_status', message)
    return project


@transaction.atomic
def resend_request(actor, active_role, project):
    """Send a change-requested project back to its client."""
    if project.status != ProjectStatus.CHANGES_REQUESTED:
        _refuse('Only a project the client asked to change is sent again.')
    if active_role != RoleOnProject.OWNER:
        raise NotAllowed('Only the owner running this project can send it again.')
    scoping.require_owner(
        project, actor, 'Only the owner running this project can send it again.',
    )

    project.status = ProjectStatus.REQUESTED
    project.save(update_fields=['status', 'updated_at'])
    waiting = project.assignments.filter(
        role_on_project=RoleOnProject.CLIENT,
        response=RequestResponse.CHANGES_REQUESTED,
    )
    for assignment in waiting:
        assignment.response = RequestResponse.PENDING
        assignment.responded_at = None
        assignment.save(update_fields=['response', 'responded_at', 'updated_at'])
        send_request(assignment)
    record(actor, 'project_request_resent', 'project', project.pk)
    return project


# --------------------------------------------------------------------------
# Assignments and requests
# --------------------------------------------------------------------------

def first_response(project, role_on_project):
    """The response a new assignment starts with (`mock_project_repository.dart:108-122`)."""
    if role_on_project == RoleOnProject.OWNER:
        return RequestResponse.ACCEPTED
    client_deciding = project.status in (
        ProjectStatus.REQUESTED, ProjectStatus.CHANGES_REQUESTED,
    )
    if role_on_project == RoleOnProject.SITE_ENGINEER and client_deciding:
        return RequestResponse.NOT_SENT
    return RequestResponse.PENDING


def _require_role_on_project(raw_role):
    if raw_role not in RoleOnProject.values:
        _refuse('Choose a role on the project.')
    return RoleOnProject(raw_role)


def _require_target_user(user_id):
    user = User.objects.filter(pk=user_id, is_active=True).first()
    if user is None:
        _refuse('Choose a person to add.')
    return user


def _require_holds_role(user, role_on_project):
    if role_on_project not in capabilities.held_roles(user):
        _refuse(f'The user does not hold the {rules.ROLE_LABELS[role_on_project]} role.')


@transaction.atomic
def assign(actor, active_role, project, payload):
    """Owner adds someone; the row starts in the role's first response."""
    if active_role != RoleOnProject.OWNER:
        raise NotAllowed('Only the owner running this project can add people to it.')
    scoping.require_owner(
        project, actor, 'Only the owner running this project can add people to it.',
    )
    role_on_project = _require_role_on_project(payload.get('role_on_project'))
    target = _require_target_user(payload.get('user_id'))
    _require_holds_role(target, role_on_project)

    # A declined row can be re-sent; a live one cannot be doubled.
    project.assignments.filter(
        user=target,
        role_on_project=role_on_project,
        response=RequestResponse.DECLINED,
    ).delete()
    if _assignment_exists(project, target, role_on_project):
        _refuse('Already on this project.')

    try:
        with transaction.atomic():
            assignment = ProjectAssignment.objects.create(
                project=project,
                user=target,
                role_on_project=role_on_project,
                response=first_response(project, role_on_project),
            )
    except IntegrityError as error:
        if not _is_unique_violation(error, ASSIGNMENT_CONSTRAINT):
            raise
        _refuse('Already on this project.')
    send_request(assignment)
    record(
        actor, 'assignment_created', 'project_assignment', assignment.pk,
        {'project': project.pk, 'role': role_on_project.value, 'user': target.pk},
    )
    return assignment


@transaction.atomic
def unassign(actor, assignment):
    """Remove a team member (owner of the project, or an admin)."""
    project_id = assignment.project_id
    assignment_id = assignment.pk
    member_id = assignment.user_id
    assignment.delete()
    record(
        actor, 'assignment_removed', 'project_assignment', assignment_id,
        {'project': project_id, 'user': member_id},
    )


@transaction.atomic
def set_user_assignments(actor, target, rows):
    """Replace one user's assignments (admin's user form)."""
    wanted = []
    for row in rows or []:
        role_on_project = _require_role_on_project((row or {}).get('role'))
        project = Project.objects.filter(pk=(row or {}).get('project_id')).first()
        if project is None or project.status == ProjectStatus.DECLINED:
            _refuse('Project not found.')
        _require_holds_role(target, role_on_project)
        wanted.append((project, role_on_project))

    existing = {
        (assignment.project_id, assignment.role_on_project): assignment
        for assignment in target.project_assignments.all()
    }
    kept = set()
    for project, role_on_project in wanted:
        key = (project.pk, role_on_project.value)
        if key in existing:
            kept.add(key)
            continue
        created = ProjectAssignment.objects.create(
            project=project,
            user=target,
            role_on_project=role_on_project,
            response=first_response(project, role_on_project),
        )
        kept.add(key)
        send_request(created)

    for key, assignment in existing.items():
        if key not in kept:
            assignment.delete()

    record(
        actor, 'user_assignments_set', 'user', target.pk,
        {'assignments': [{'project': project.pk, 'role': role.value}
                         for project, role in wanted]},
    )
    return target.project_assignments.select_related('project').order_by('pk')


def _accept_if_ready(project):
    """Move `site_engineer_pending` to `accepted` once an SE joined and none is pending."""
    if project.status != ProjectStatus.SITE_ENGINEER_PENDING:
        return
    involved = project.assignments.filter(
        role_on_project__in=[RoleOnProject.CLIENT, RoleOnProject.SITE_ENGINEER],
    )
    has_engineer = involved.filter(
        role_on_project=RoleOnProject.SITE_ENGINEER,
        response=RequestResponse.ACCEPTED,
    ).exists()
    still_waiting = involved.filter(response=RequestResponse.PENDING).exists()
    if not has_engineer or still_waiting:
        return
    project.status = ProjectStatus.ACCEPTED
    project.save(update_fields=['status', 'updated_at'])
    notify_owners(
        project,
        f'{project.code} is accepted by the client and the site engineer. '
        'Start it when work begins.',
    )


@transaction.atomic
def respond(actor, active_role, assignment, payload):
    """Answer a project request: accept, decline, or ask for changes (client only)."""
    if assignment.user_id != actor.pk:
        from rest_framework.exceptions import NotFound

        raise NotFound()
    if assignment.response != RequestResponse.PENDING:
        _refuse('You already answered this request.')

    raw = payload.get('response')
    if raw not in RequestResponse.values:
        _refuse('Accept, decline or ask for changes.')
    answer = RequestResponse(raw)
    if answer not in rules.ANSWERABLE:
        _refuse('Accept, decline or ask for changes.')

    is_client = assignment.role_on_project == RoleOnProject.CLIENT
    if answer == RequestResponse.CHANGES_REQUESTED and not is_client:
        raise NotAllowed('Only the client can ask for changes.')

    note = payload.get('note')
    note = None if note is None else _text(note)
    if answer in (RequestResponse.DECLINED, RequestResponse.CHANGES_REQUESTED) and not note:
        _refuse('Add a note so the owner knows why.')

    assignment.response = answer
    assignment.note = None if answer == RequestResponse.ACCEPTED else note
    assignment.responded_at = timezone.now()
    assignment.save(update_fields=['response', 'note', 'responded_at', 'updated_at'])

    project = assignment.project
    who = actor.full_name
    record(
        actor, f'project_request_{answer.value}', 'project', project.pk,
        {'role': assignment.role_on_project, 'note': assignment.note},
    )

    if is_client:
        if answer == RequestResponse.DECLINED:
            previous = project.status
            project.status = ProjectStatus.DECLINED
            project.save(update_fields=['status', 'updated_at'])
            record(
                actor, 'project_status_changed', 'project', project.pk,
                {'from': previous, 'to': ProjectStatus.DECLINED.value},
            )
            notify_owners(
                project,
                f'{who} declined {project.code} {project.name}. Reason: {note}',
                link=PROJECTS_LINK,
            )
        elif answer == RequestResponse.CHANGES_REQUESTED:
            project.status = ProjectStatus.CHANGES_REQUESTED
            project.save(update_fields=['status', 'updated_at'])
            notify_owners(
                project, f'{who} asked for changes on {project.code}: {note}',
            )
        else:
            project.status = ProjectStatus.SITE_ENGINEER_PENDING
            project.save(update_fields=['status', 'updated_at'])
            notify_owners(
                project,
                f'{who} accepted {project.code}. '
                'The site engineer has been sent the request.',
            )
            for waiting in project.assignments.filter(
                response=RequestResponse.NOT_SENT,
            ):
                waiting.response = RequestResponse.PENDING
                waiting.save(update_fields=['response', 'updated_at'])
                send_request(waiting)
            _accept_if_ready(project)
        return assignment

    owner_link = None
    if answer == RequestResponse.DECLINED:
        notify_owners(
            project,
            f'{who} declined {project.code}: {note} Choose another site engineer.',
            link=owner_link,
        )
    else:
        notify_owners(project, f'{who} accepted {project.code}.', link=owner_link)
        _accept_if_ready(project)
    return assignment


# --------------------------------------------------------------------------
# Categories and to-dos
# --------------------------------------------------------------------------

def _category_budget_total(project, exclude_pk=None):
    total = 0
    for category in project.categories.exclude(pk=exclude_pk):
        total += category.budget or 0
    return total


@transaction.atomic
def save_category(project, payload, category=None):
    """Create or edit one category of `project`."""
    if not _text(payload.get('name', category.name if category else '')):
        _refuse('Enter a category name.')
    raw_budget = payload.get('budget', category.budget if category else None)
    budget = None if raw_budget is None else as_decimal(raw_budget)
    if raw_budget is not None and budget is None:
        _refuse('Budget cannot be negative.')
    if budget is not None and budget < 0:
        _refuse('Budget cannot be negative.')
    total = _category_budget_total(project, exclude_pk=category.pk if category else None)
    total += budget or 0
    if total > project.contract_amount:
        _refuse(
            f'Total category budgets ({peso(total)}) would exceed the contract '
            f'amount ({peso(project.contract_amount)}).'
        )

    if category is None:
        category = Category(project=project)
    category.name = _text(payload.get('name', category.name))
    category.budget = budget
    if payload.get('sort_order') is not None:
        try:
            category.sort_order = int(payload['sort_order'])
        except (TypeError, ValueError):
            _refuse('Choose a sort order.')
    category.save()
    return category


@transaction.atomic
def delete_category(category):
    if category.todos.filter(is_verified=True).exists():
        _refuse('This category has verified to-dos and cannot be deleted.')
    category.delete()


def _validate_todo(category, project, payload, todo=None):
    title = payload.get('title', todo.title if todo else None)
    if not _text(title):
        _refuse('Enter a to-do title.')
    start = _date(payload.get('start_date', todo.start_date if todo else None))
    end = _date(payload.get('end_date', todo.end_date if todo else None))
    if start is None or end is None:
        _refuse('Choose start and end dates.')
    if end < start:
        _refuse('End date must be on or after the start date.')
    if project.start_date and project.target_end_date and (
        start < project.start_date or end > project.target_end_date
    ):
        _refuse(
            f'Dates must fall within the project schedule '
            f'({project.start_date.isoformat()} to '
            f'{project.target_end_date.isoformat()}).'
        )
    return _text(title), start, end


@transaction.atomic
def save_todo(category, payload, todo=None):
    """Create or edit a to-do; done/verified flags stay server-only."""
    project = category.project
    title, start, end = _validate_todo(category, project, payload, todo)
    if todo is None:
        todo = Todo(category=category, title=title, start_date=start, end_date=end)
    else:
        todo.title = title
        todo.start_date = start
        todo.end_date = end
        todo.category = category
    todo.save()
    return todo


@transaction.atomic
def delete_todo(todo):
    if todo.is_verified:
        _refuse('A verified to-do cannot be deleted. Un-verify it first.')
    todo.delete()


@transaction.atomic
def set_todo_done(actor, todo, done):
    """SE or owner ticks a to-do; `done` is the only client-settable value."""
    if not done and todo.is_verified:
        _refuse('This to-do is verified. The owner must un-verify it first.')
    if todo.is_done == done:
        return todo

    todo.is_done = done
    todo.done_by = actor if done else None
    todo.done_at = timezone.now() if done else None
    todo.save(update_fields=['is_done', 'done_by', 'done_at', 'updated_at'])
    record(
        actor,
        'todo_marked_done' if done else 'todo_marked_not_done',
        'todo', todo.pk,
    )
    if done:
        notify_project_role(
            todo.category.project, RoleOnProject.OWNER,
            f'"{todo.title}" was marked done on '
            f'{todo.category.project.code}. Verify it.',
            type='todo_done',
            link=TODO_VERIFICATION_LINK,
        )
    return todo


@transaction.atomic
def verify_todo(actor, todo):
    if todo.is_verified:
        _refuse('This to-do is already verified.')
    if not todo.is_done:
        _refuse('Only to-dos marked done can be verified.')

    todo.is_verified = True
    todo.verified_by = actor
    todo.verified_at = timezone.now()
    todo.save(update_fields=['is_verified', 'verified_by', 'verified_at', 'updated_at'])
    record(actor, 'todo_verified', 'todo', todo.pk)
    return todo


@transaction.atomic
def unverify_todo(actor, todo, raw_reason):
    if not todo.is_verified:
        _refuse('This to-do is not verified.')
    reason = _text(raw_reason)
    if not reason:
        _refuse('Enter a reason for un-verifying.')

    todo.is_verified = False
    todo.verified_by = None
    todo.verified_at = None
    todo.save(update_fields=['is_verified', 'verified_by', 'verified_at', 'updated_at'])
    record(actor, 'todo_unverified', 'todo', todo.pk, {'reason': reason})
    return todo


# --------------------------------------------------------------------------
# Client records (task 5.3)
# --------------------------------------------------------------------------

CLIENT_CONSTRAINT = 'client_record_id_key'   # Client.user OneToOne (unique)
_EMAIL = re.compile(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')


def _require_free_name(name, exclude_pk=None):
    taken = Client.objects.filter(name__iexact=name)
    if exclude_pk is not None:
        taken = taken.exclude(pk=exclude_pk)
    if taken.exists():
        _refuse(rules.CLIENT_NAME_TAKEN)
    return name


def _client_values(payload, creating):
    """Validate the editable client columns; a blank optional column is `''`.

    A create sends every column; an update only touches the keys it names, so a
    PATCH of just the contact person never has to resend the name.
    """
    values = {}
    if creating or 'name' in payload:
        name = _text(payload.get('name'))
        if not name:
            _refuse(rules.CLIENT_NAME_REQUIRED)
        values['name'] = name
    for field in ('email', *rules.CLIENT_TEXT_FIELDS):
        if not creating and field not in payload:
            continue
        value = _text(payload.get(field))
        if field == 'email':
            if value and not _EMAIL.match(value):
                _refuse(rules.CLIENT_EMAIL)
        else:
            label, limit = rules.CLIENT_TEXT_FIELDS[field]
            if len(value) > limit:
                _refuse(
                    rules.CLIENT_FIELD_TOO_LONG.format(limit=limit, label=label)
                )
        values[field] = value
    return values


def _require_link_route(payload):
    """`user_id` is not part of the create/update body (a link has its own route)."""
    if payload.get('user_id') not in (None, ''):
        _refuse(rules.CLIENT_LINK_SEPARATE)


@transaction.atomic
def create_client(actor, payload):
    """Create a client record; Admin/Owner only (checked by the view)."""
    _require_link_route(payload)
    values = _client_values(payload, creating=True)
    _require_free_name(values['name'])
    client = Client.objects.create(**values)
    record(actor, 'client_created', 'client', client.pk, {'name': client.name})
    return client


@transaction.atomic
def update_client(actor, client, payload):
    """Rename / re-contact a client; the portal login is left where it is."""
    _require_link_route(payload)
    values = _client_values(payload, creating=False)
    if 'name' in values:
        _require_free_name(values['name'], exclude_pk=client.pk)
    for field, value in values.items():
        setattr(client, field, value)
    client.save(update_fields=[*values, 'updated_at'])
    record(actor, 'client_updated', 'client', client.pk, {'name': client.name})
    return client


def _require_client_login(raw_user_id):
    """The user to link: exists, and holds the client role."""
    try:
        user_id = int(raw_user_id)
    except (TypeError, ValueError):
        _refuse(rules.CLIENT_USER_REQUIRED)
    user = User.objects.filter(pk=user_id).first()
    if user is None:
        _refuse(rules.CLIENT_USER_UNKNOWN)
    if Role.CLIENT not in capabilities.held_roles(user):
        _refuse(
            f'The user does not hold the {rules.ROLE_LABELS[RoleOnProject.CLIENT]} role.'
        )
    return user


@transaction.atomic
def link_client_user(actor, client, raw_user_id):
    """Attach one portal login to this client; a login belongs to one client.

    Assigning a login that already sits on another client moves it, which is
    what the mock's `linkUser` does (`mock_client_repository.dart:60-73`).
    """
    user = _require_client_login(raw_user_id)
    if client.user_id is not None and client.user_id != user.pk:
        _refuse(rules.CLIENT_LOGIN_TAKEN)
    # Release the login from any other client first (the DB allows one row).
    Client.objects.filter(user=user).exclude(pk=client.pk).update(user=None)
    client.user = user
    try:
        with transaction.atomic():
            client.save(update_fields=['user', 'updated_at'])
    except IntegrityError as error:
        if not _is_unique_violation(error, CLIENT_CONSTRAINT):
            raise
        _refuse(rules.CLIENT_LOGIN_TAKEN)
    record(
        actor, 'client_user_linked', 'client', client.pk,
        {'name': client.name, 'user': user.pk},
    )
    return client


@transaction.atomic
def unlink_client_user(actor, client):
    """Detach the portal login; a client without one is a no-op."""
    user_id = client.user_id
    if user_id is None:
        return client
    client.user = None
    client.save(update_fields=['user', 'updated_at'])
    record(
        actor, 'client_user_unlinked', 'client', client.pk,
        {'name': client.name, 'user': user_id},
    )
    return client
