"""Transactional site-report operations: drafts, the review workflow and uploads.

Everything that changes a report, its children, a photo or a document happens
here inside `transaction.atomic()`, so the state change, its audit row and its
notification either all land or none do. Views only pick the scoped queryset,
check the role/author and call one of these.

Two ordering rules from the task brief:

* **no write before a refusal** — every nested id is resolved and every row is
  validated first, so a bad `material_id` cannot leave a half-saved report;
* **the author is the only editor** — checked before the state change
  (decision 06 R6), and the server clock is `timezone.localdate()`
  (`Asia/Manila`, decision 06 #11).
"""

# Pyright here runs without django-stubs, so model managers/FKs are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportOptionalMemberAccess=false

from datetime import date, datetime
from typing import NoReturn

from django.db import IntegrityError, transaction
from django.utils import timezone

from ..master_data.models import EquipmentItem, MaterialItem
from ..projects import scoping
from ..projects.models import ProjectStatus, RoleOnProject, Todo
from ..projects.rules import NotAllowed, RuleRefused
from ..projects.services import notify_owners
from ..projects.services import set_todo_done as mark_todo_done
from ..projects.services import verify_todo as verify_project_todo
from ..users import capabilities
from ..users.services import notify, record
from . import rules, uploads
from .models import (
    DailyReport,
    Document,
    DocumentType,
    EquipmentLog,
    Issue,
    IssueReason,
    IssueType,
    ReportManpower,
    ReportMaterialUsage,
    ReportPhoto,
    Weather,
)

REPORTS_LINK = '/daily-reports'
DOCUMENT_CONSTRAINT = 'apps_site_reports_document_name_ci_unique'
REPORT_DATE_CONSTRAINT = 'unique_report_per_project_date'


def _text(value):
    return '' if value is None else str(value).strip()


def _refuse(message) -> NoReturn:
    raise RuleRefused(message)


def _discard_file(instance):
    """Remove the file a *failed* save just wrote; never touches a stored one."""
    if instance.file:
        instance.file.delete(save=False)


def _delete_file_on_commit(field_file):
    """Delete a replaced file only once the row change is committed.

    Deleting inside the transaction lets a later rollback leave rows pointing
    at files that are already gone; the callback runs after the commit instead.
    """
    transaction.on_commit(lambda: field_file.delete(save=False))


def report_link(report):
    """AppRoutes.dailyReport(id)."""
    return f'{REPORTS_LINK}/{report.pk}'


def _format_date(value):
    return value.isoformat()


def _as_date(value):
    """Parse a `yyyy-MM-dd` string (or a date) into a date, or None."""
    if value in (None, ''):
        return None
    if hasattr(value, 'year') and hasattr(value, 'month'):
        return value
    try:
        return date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def _as_timestamp(value):
    """Parse an ISO-8601 timestamp; None when absent or unparseable."""
    if value in (None, ''):
        return None
    if hasattr(value, 'year') and hasattr(value, 'tzinfo'):
        return value
    try:
        parsed = datetime.fromisoformat(str(value).replace('Z', '+00:00'))
    except ValueError:
        return None
    if timezone.is_naive(parsed):
        parsed = timezone.make_aware(parsed, timezone.get_current_timezone())
    return parsed


def _is_unique_violation(error, *names):
    message = str(error)
    return any(name in message for name in names)


# --------------------------------------------------------------------------
# Daily reports — validation (nothing here writes)
# --------------------------------------------------------------------------

def _validate_report_date(report_date):
    """No future date, judged by the server's Manila date (decision 06 #11)."""
    if report_date is None:
        _refuse('Choose the report date.')
    if report_date > timezone.localdate():
        _refuse('A daily report cannot be dated in the future.')


def _require_ongoing(project):
    if project.status != ProjectStatus.ONGOING:
        label = ProjectStatus(project.status).label
        _refuse(
            'Daily reports can be added only while the project is Ongoing '
            f'(it is {label}).'
        )


def _require_filing_engineer(project, actor, active_role):
    """Filing needs the **active** `site_engineer` role and an accepted row.

    Holding the assignment is not enough: a user who is also an owner and acts
    as `owner` gets owner rights only (contract security check 4).
    """
    if active_role != RoleOnProject.SITE_ENGINEER:
        raise NotAllowed(rules.NOT_THE_ENGINEER)
    if not scoping.has_accepted_assignment(project, actor, RoleOnProject.SITE_ENGINEER):
        raise NotAllowed(rules.NOT_THE_ENGINEER)


def _duplicate_exists(project, report_date, report=None):
    queryset = DailyReport.objects.filter(
        project=project, report_date=report_date,
    )
    if report is not None:
        queryset = queryset.exclude(pk=report.pk)
    return queryset.exists()


def _validate_manpower(rows):
    cleaned = []
    for row in rows or []:
        headcount = rules.as_int(row.get('headcount'))
        if headcount is None or headcount <= 0:
            _refuse('Headcount must be greater than 0.')
        trade = _text(row.get('trade'))
        if not trade:
            _refuse('Choose a trade for each manpower row.')
        cleaned.append((trade, headcount))
    return cleaned


def _validate_materials(rows):
    cleaned = []
    for row in rows or []:
        material = MaterialItem.objects.filter(
            pk=rules.as_int(row.get('material_id')),
        ).first()
        if material is None:
            _refuse(rules.CHOOSE_MATERIAL)
        quantity = rules.as_decimal(row.get('quantity'))
        if quantity is None or quantity <= 0:
            _refuse('Quantity must be greater than 0.')
        cleaned.append((material, quantity))
    return cleaned


def _validate_equipment(rows):
    cleaned = []
    for row in rows or []:
        equipment = EquipmentItem.objects.filter(
            pk=rules.as_int(row.get('equipment_id')),
        ).first()
        if equipment is None:
            _refuse(rules.CHOOSE_EQUIPMENT)
        hours = rules.as_decimal(row.get('hours_used'))
        if hours is None or hours <= 0:
            _refuse('Hours must be greater than 0.')
        if hours > 24:
            _refuse('Hours cannot exceed 24 in a day.')
        cleaned.append((equipment, hours))
    return cleaned


def _validate_issues(rows):
    cleaned = []
    for row in rows or []:
        issue_type = _text(row.get('type'))
        reason = _text(row.get('reason'))
        if issue_type not in IssueType.values:
            _refuse(rules.CHOOSE_ISSUE_TYPE)
        if reason not in IssueReason.values:
            _refuse(rules.CHOOSE_ISSUE_REASON)
        description = _text(row.get('description'))
        if not description:
            _refuse('Describe each issue.')
        days_lost = rules.as_decimal(row.get('days_lost', 0))
        if days_lost is None or days_lost < 0:
            _refuse('Days lost cannot be negative.')
        cleaned.append((issue_type, reason, description, days_lost))
    return cleaned


def _validate_todos(project, raw_ids, report=None):
    """Resolve the chosen to-dos inside the project; refuse before writing."""
    chosen = []
    current = report.pk if report is not None else None
    for raw in raw_ids or []:
        todo = Todo.objects.filter(
            category__project=project, pk=rules.as_int(raw),
        ).first()
        if todo is None:
            _refuse(rules.CHOOSE_TODO)
        if todo.is_done and todo.daily_report_id != current:
            _refuse(f'"{todo.title}" is already done.')
        if todo not in chosen:
            chosen.append(todo)
    return chosen


def _validate_weather(value):
    if value not in Weather.values:
        _refuse(rules.CHOOSE_WEATHER)
    return value


def _validate_photo_selection(rows):
    """Rows that keep existing photos: `{id, caption, latitude, longitude, taken_at}`."""
    cleaned = []
    for row in rows or []:
        cleaned.append({
            'id': rules.as_int(row.get('id')),
            'caption': _text(row.get('caption')) or None,
            'latitude': rules.as_decimal(row.get('latitude')),
            'longitude': rules.as_decimal(row.get('longitude')),
            'taken_at': _as_timestamp(row.get('taken_at')),
        })
    return cleaned


# --------------------------------------------------------------------------
# Daily reports — draft save
# --------------------------------------------------------------------------

def _apply_children(report, manpower, materials, equipment, issues):
    """Replace every child list with the validated rows (the mock's behaviour)."""
    report.manpower.all().delete()
    ReportManpower.objects.bulk_create([
        ReportManpower(daily_report=report, trade=trade, headcount=headcount)
        for trade, headcount in manpower
    ])
    report.materials.all().delete()
    ReportMaterialUsage.objects.bulk_create([
        ReportMaterialUsage(daily_report=report, material=material, quantity=quantity)
        for material, quantity in materials
    ])
    report.equipment.all().delete()
    EquipmentLog.objects.bulk_create([
        EquipmentLog(
            daily_report=report, equipment=equipment, project=report.project,
            log_date=report.report_date, hours_used=hours,
        )
        for equipment, hours in equipment
    ])
    report.issues.all().delete()
    Issue.objects.bulk_create([
        Issue(
            daily_report=report, project=report.project, type=issue_type,
            reason=reason, description=description, days_lost=days_lost,
        )
        for issue_type, reason, description, days_lost in issues
    ])


def _apply_photos(report, selection):
    """Delete the photos the draft dropped (and their files), keep the rest."""
    keep_ids = {row['id'] for row in selection if row['id'] is not None}
    for photo in list(report.photos.all()):
        if photo.pk not in keep_ids:
            _delete_file_on_commit(photo.file)
            photo.delete()
    by_id = {photo.pk: photo for photo in report.photos.all()}
    for row in selection:
        photo = by_id.get(row['id'])
        if photo is None:
            continue
        changed = []
        for field in ('caption', 'latitude', 'longitude', 'taken_at'):
            value = row[field]
            if value is not None and getattr(photo, field) != value:
                setattr(photo, field, value)
                changed.append(field)
        if changed:
            photo.save(update_fields=[*changed, 'updated_at'])


def _apply_todos(report, chosen):
    """Link the chosen to-dos; unlink ones no longer chosen that are still open."""
    chosen_ids = {todo.pk for todo in chosen}
    for todo in chosen:
        if todo.daily_report_id != report.pk:
            todo.daily_report = report
            todo.save(update_fields=['daily_report', 'updated_at'])
    for todo in report.todos.exclude(pk__in=chosen_ids).filter(is_done=False):
        todo.daily_report = None
        todo.save(update_fields=['daily_report', 'updated_at'])


@transaction.atomic
def save_draft(actor, active_role, payload, report=None, project=None):
    """Create or update a draft, replacing its children (site engineer only).

    `active_role` is the caller's `X-Active-Role`: editing and filing are
    site-engineer actions, so an owner acting as `owner` is refused even when
    the same account also holds `site_engineer`.
    """
    if report is None:
        _require_ongoing(project)
        _require_filing_engineer(project, actor, active_role)
        target_project = project
    else:
        target_project = report.project
        if active_role != RoleOnProject.SITE_ENGINEER:
            raise NotAllowed(rules.NOT_THE_AUTHOR_EDIT)
        if report.submitted_by_id != actor.pk:
            raise NotAllowed(rules.NOT_THE_AUTHOR_EDIT)
        if not report.is_editable:
            _refuse(rules._can_edit_message(report.status))

    report_date = _as_date(payload.get('report_date'))
    _validate_report_date(report_date)
    if _duplicate_exists(target_project, report_date, report):
        _refuse('There is already a report for this project on this date.')

    weather = _validate_weather(payload.get('weather'))
    manpower = _validate_manpower(payload.get('manpower'))
    materials = _validate_materials(payload.get('materials'))
    equipment = _validate_equipment(payload.get('equipment'))
    issues = _validate_issues(payload.get('issues'))
    photos = _validate_photo_selection(payload.get('photos'))
    todos = _validate_todos(target_project, payload.get('todo_ids'), report)

    if report is None:
        report = DailyReport(
            project=target_project,
            submitted_by=actor,
            status='draft',
        )
    report.report_date = report_date
    report.weather = weather
    report.toolbox_meeting_held = bool(payload.get('toolbox_meeting_held'))
    try:
        with transaction.atomic():
            report.save()
    except IntegrityError as error:
        if not _is_unique_violation(error, REPORT_DATE_CONSTRAINT):
            raise
        _refuse('There is already a report for this project on this date.')

    _apply_children(report, manpower, materials, equipment, issues)
    _apply_photos(report, photos)
    _apply_todos(report, todos)
    return report


# --------------------------------------------------------------------------
# Daily reports — review workflow
# --------------------------------------------------------------------------

@transaction.atomic
def submit(actor, active_role, report):
    """The author sends the report to the PM; its linked to-dos become done."""
    if not report.is_editable:
        _refuse(rules.CANNOT_SUBMIT)
    if active_role != RoleOnProject.SITE_ENGINEER:
        raise NotAllowed(rules.NOT_THE_AUTHOR_SUBMIT)
    if report.submitted_by_id != actor.pk:
        raise NotAllowed(rules.NOT_THE_AUTHOR_SUBMIT)

    for todo in report.todos.filter(is_done=False):
        mark_todo_done(actor, todo, True)

    report.status = 'submitted'
    report.save(update_fields=['status', 'updated_at'])
    record(actor, 'daily_report_submitted', 'daily_report', report.pk)
    notify_owners(
        report.project,
        f'Daily report for {report.project.code} on '
        f'{_format_date(report.report_date)} is waiting for your approval.',
        link=report_link(report),
        type='report_submitted',
    )
    return report


def _require_reviewable(actor, report):
    if report.status != 'submitted':
        _refuse(rules.CANNOT_REVIEW)
    scoping.require_owner(report.project, actor, rules.NOT_THE_OWNER_REVIEW)


@transaction.atomic
def approve(actor, report):
    """The owner approves: linked to-dos are verified and the author is told."""
    _require_reviewable(actor, report)

    for todo in report.todos.filter(is_done=True, is_verified=False):
        verify_project_todo(actor, todo)

    report.status = 'approved'
    report.reviewed_by = actor
    report.remarks = None
    report.save(update_fields=['status', 'reviewed_by', 'remarks', 'updated_at'])
    record(actor, 'daily_report_approved', 'daily_report', report.pk)
    notify(
        report.submitted_by, 'report_approved',
        f'Your daily report for {_format_date(report.report_date)} was approved.',
        link=report_link(report),
    )
    return report


@transaction.atomic
def return_report(actor, report, raw_remarks):
    """The owner returns the report with remarks the site engineer must fix."""
    _require_reviewable(actor, report)
    remarks = _text(raw_remarks)
    if not remarks:
        _refuse(rules.RETURN_REMARKS)

    report.status = 'returned'
    report.reviewed_by = actor
    report.remarks = remarks
    report.save(update_fields=['status', 'reviewed_by', 'remarks', 'updated_at'])
    record(
        actor, 'daily_report_returned', 'daily_report', report.pk,
        {'remarks': remarks},
    )
    notify(
        report.submitted_by, 'report_returned',
        f'Your daily report for {_format_date(report.report_date)} was returned: '
        f'{remarks}',
        link=report_link(report),
    )
    return report


# --------------------------------------------------------------------------
# Report photos
# --------------------------------------------------------------------------

@transaction.atomic
def upload_photo(actor, report, upload, payload):
    """The author adds a photo; only while the report is draft/returned."""
    if report.submitted_by_id != actor.pk:
        raise NotAllowed(rules.NOT_THE_AUTHOR_PHOTO)
    if not report.is_editable:
        _refuse(rules._can_edit_message(report.status))

    file_name, _extension = uploads.check_photo(upload)
    photo = ReportPhoto(
        daily_report=report,
        file_name=file_name,
        caption=_text(payload.get('caption')) or None,
        latitude=rules.as_decimal(payload.get('latitude')),
        longitude=rules.as_decimal(payload.get('longitude')),
        taken_at=_as_timestamp(payload.get('taken_at')) or timezone.now(),
    )
    photo.file.save(file_name, upload, save=False)
    try:
        photo.save()
    except Exception:
        # The row is gone: drop the file that was just written instead of an orphan.
        _discard_file(photo)
        raise
    return photo


# --------------------------------------------------------------------------
# Documents
# --------------------------------------------------------------------------

def can_upload_documents(project, actor, active_role):
    """Owner or site engineer of the project, in the active role."""
    if not scoping.has_accepted_assignment(project, actor, active_role):
        return False
    return active_role in ('owner', 'site_engineer')


def _require_can_upload(project, actor, active_role):
    if not can_upload_documents(project, actor, active_role):
        raise NotAllowed(rules.NOT_AN_UPLOADER)


@transaction.atomic
def upload_document(actor, active_role, project, upload, payload):
    """Store a private document; contract rows are finance-only."""
    _require_can_upload(project, actor, active_role)

    name = _text(payload.get('name'))
    if not name:
        _refuse(rules.DOCUMENT_NAME_REQUIRED)
    doc_type = rules.document_type(payload.get('doc_type'))
    if doc_type is None:
        _refuse(rules.CHOOSE_SECTION)
    if doc_type == DocumentType.CONTRACT and not capabilities.manages_finance(active_role):
        raise NotAllowed(rules.NOT_A_CONTRACT_FILER)

    # Mock order: name, then the file (extension/content/size), then the
    # duplicate-name rule (`mock_document_repository.dart:99-118`).
    file_name, _extension = uploads.check_document(upload)

    if Document.objects.filter(
        project=project, doc_type=doc_type, name__iexact=name,
    ).exists():
        _refuse(rules.DUPLICATE_DOCUMENT)

    document = Document(
        project=project,
        name=name,
        doc_type=doc_type,
        file_name=file_name,
        uploaded_by=actor,
    )
    try:
        with transaction.atomic():
            document.file.save(file_name, upload, save=False)
            document.save()
            record(
                actor, 'document_uploaded', 'document', document.pk,
                {'project': project.pk, 'doc_type': doc_type},
            )
    except IntegrityError as error:
        _discard_file(document)
        if not _is_unique_violation(error, DOCUMENT_CONSTRAINT):
            raise
        _refuse(rules.DUPLICATE_DOCUMENT)
    except Exception:
        # The row never committed: drop the stored file rather than orphan it.
        _discard_file(document)
        raise
    return document


@transaction.atomic
def delete_document(actor, document):
    """The uploader or the project's accepted owner removes a document."""
    uploader = document.uploaded_by_id == actor.pk
    owner = scoping.has_accepted_assignment(document.project, actor, 'owner')
    if not uploader and not owner:
        raise NotAllowed(rules.NOT_A_DELETER)

    document_id = document.pk
    project_id = document.project_id
    _delete_file_on_commit(document.file)
    document.delete()
    record(
        actor, 'document_deleted', 'document', document_id,
        {'project': project_id},
    )
