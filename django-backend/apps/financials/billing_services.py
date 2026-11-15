"""Billing writes: every change is one transaction with its audit row.

Lock order is fixed to avoid deadlocks: the **project** row first (billing
numbering, VO numbering, retention balances), then the billing/VO row being
changed. A refused change leaves no row, no audit and no half-applied money.

Actions and their refusal texts mirror `mock_billing_repository.dart`; the
database constraints in `models.py` are the backstop for two simultaneous
requests that slip past the lock-free reads.
"""

# Pyright here runs without django-stubs, so model managers are untyped.
# pyright: reportAttributeAccessIssue=false, reportArgumentType=false

from decimal import Decimal

from django.db import IntegrityError, transaction
from django.db.models import Max, Sum
from django.utils import timezone

from ..projects.models import Project, RoleOnProject
from ..projects.rules import RuleRefused
from ..projects.services import notify_project_role
from ..users import services as user_services
from . import billing_math
from . import billing_rules as rules
from .models import (
    BILLED_STATUSES,
    IN_PROGRESS_BILLING_STATUSES,
    RETENTION_HELD_STATUSES,
    BillingStatus,
    ClientPayment,
    ProgressBilling,
    RetentionRelease,
    VariationOrder,
    VariationOrderStatus,
)


def _tell(project, role_on_project, type, message, link):
    """Notify the project's accepted members in one role, in the caller's transaction.

    The mock told the other party at each hand-off; doing it here keeps the
    message and the status change atomic, so a refused or rolled-back action
    sends nothing.
    """
    notify_project_role(project, role_on_project, message, type=type, link=link)


def _refuse(message):
    """Raise the mock's `400 {"detail": ...}` refusal."""
    raise RuleRefused(message)


def _require(rule_text):
    """Raise `rule_text` when it is a refusal (not None)."""
    if rule_text is not None:
        raise RuleRefused(rule_text)


def _locked_project(project):
    return Project.objects.select_for_update().get(pk=project.pk)


def _locked_billing(billing):
    return ProgressBilling.objects.select_for_update().get(pk=billing.pk)


# --- Progress billings -------------------------------------------------------


def create_billing(user, project, period_end):
    """A draft billing from verified progress as of `period_end`."""
    with transaction.atomic():
        project = _locked_project(project)
        _require(rules.require_billable(project))
        _require(rules.validate_pct_burden(
            project.down_payment_pct, project.retention_pct,
        ))
        if ProgressBilling.objects.filter(
            project=project, status__in=IN_PROGRESS_BILLING_STATUSES,
        ).exists():
            _refuse(rules.IN_PROGRESS)
        _require(rules.validate_period_end(
            period_end, timezone.localdate(),
            billing_math.previous_period_end(project),
        ))

        figures = billing_math.preview(project, period_end)
        _require(rules.validate_accomplishment(
            figures['pct_accomplished'], figures['this_period'],
        ))

        next_no = ProgressBilling.objects.filter(project=project).aggregate(
            latest=Max('billing_no'),
        )['latest'] or 0
        # `this_period` is a derived property, not a column.
        figures.pop('this_period')
        try:
            billing = ProgressBilling.objects.create(
                project=project,
                billing_no=next_no + 1,
                period_end=period_end,
                status=BillingStatus.DRAFT,
                **figures,
            )
        except IntegrityError as error:
            # The one-in-progress partial unique index fired: another request
            # created a billing between our check and this insert.
            raise RuleRefused(rules.IN_PROGRESS) from error

        user_services.record(user, 'billing_created', 'progress_billing', billing.pk)
    return billing


def submit_billing(user, billing):
    with transaction.atomic():
        billing = _locked_billing(billing)
        if billing.status not in (BillingStatus.DRAFT, BillingStatus.DISPUTED):
            _refuse(rules.ONLY_DRAFT_SUBMITTED)
        billing.status = BillingStatus.PENDING_CLIENT
        billing.save(update_fields=['status', 'updated_at'])
        user_services.record(user, 'billing_submitted', 'progress_billing', billing.pk)
        _tell(
            billing.project, RoleOnProject.CLIENT, 'billing',
            f'Progress billing #{billing.billing_no} for {billing.project.name} '
            'is ready for your review.',
            f'/client/billings/{billing.pk}',
        )
    return billing


def withdraw_billing(user, billing):
    with transaction.atomic():
        billing = _locked_billing(billing)
        if billing.status not in (BillingStatus.DRAFT, BillingStatus.DISPUTED):
            _refuse(rules.ONLY_DRAFT_WITHDRAWN)
        billing.status = BillingStatus.REJECTED
        billing.save(update_fields=['status', 'updated_at'])
        user_services.record(user, 'billing_withdrawn', 'progress_billing', billing.pk)
    return billing


def _answer_billing(billing, expected, new_status, action, user, reason=None):
    with transaction.atomic():
        billing = _locked_billing(billing)
        if billing.status != expected:
            _refuse(rules.EXPECT_PENDING_CLIENT.format(
                current=billing.get_status_display().lower(),
            ))
        billing.status = new_status
        billing.save(update_fields=['status', 'updated_at'])
        details = {'reason': reason.strip()} if reason else None
        user_services.record(user, action, 'progress_billing', billing.pk, details)
        if new_status == BillingStatus.DISPUTED:
            _tell(
                billing.project, RoleOnProject.OWNER, 'billing',
                f'The client disputed billing #{billing.billing_no}: '
                f'{reason.strip()}',
                f'/billings/{billing.pk}',
            )
    return billing


def client_approve_billing(user, billing):
    """Approve on the client's side.

    Refused while the project's down payment + retention leave no payable net
    due: such an `approved` billing can never be paid and never frees the
    project for the next one.
    """
    project = billing.project
    _require(rules.validate_pct_burden(
        project.down_payment_pct, project.retention_pct,
    ))
    return _answer_billing(
        billing, BillingStatus.PENDING_CLIENT, BillingStatus.APPROVED,
        'billing_client_approved', user,
    )


def client_dispute_billing(user, billing, reason):
    _require(rules.REASON if not str(reason or '').strip() else None)
    return _answer_billing(
        billing, BillingStatus.PENDING_CLIENT, BillingStatus.DISPUTED,
        'billing_client_disputed', user, reason=reason,
    )


# --- Client payments ---------------------------------------------------------


def record_payment(user, billing, amount, paid_on, method, reference_no=''):
    """Record the client's money; overpayment is impossible under the lock.

    The billing row is locked, the recorded sum re-read inside the transaction,
    and the amount compared with the remaining balance — two simultaneous
    payments can never exceed `net_due`.
    """
    with transaction.atomic():
        billing = _locked_billing(billing)
        if billing.status != BillingStatus.APPROVED:
            _refuse(rules.PAYMENT_APPROVED_ONLY)
        paid = billing.payments.aggregate(total=Sum('amount'))['total'] or Decimal('0.00')
        balance = billing.net_due - paid
        _require(rules.validate_payment(amount, balance))

        payment = ClientPayment.objects.create(
            progress_billing=billing, amount=amount, paid_on=paid_on,
            method=method, reference_no=(reference_no or '').strip(),
        )
        user_services.record(
            user, 'billing_payment_recorded', 'progress_billing', billing.pk,
            {'amount': f'{amount:.2f}'},
        )
        if balance - amount <= Decimal('0.00'):
            billing.status = BillingStatus.PAID
            billing.save(update_fields=['status', 'updated_at'])
            user_services.record(user, 'billing_paid', 'progress_billing', billing.pk)
    return payment


def billing_summary(project_ids):
    """`{billed, collected}` over the given projects (None = every project)."""
    billings = ProgressBilling.objects.filter(status__in=BILLED_STATUSES)
    payments = ClientPayment.objects.all()
    if project_ids is not None:
        billings = billings.filter(project_id__in=project_ids)
        payments = payments.filter(progress_billing__project_id__in=project_ids)
    return {
        'billed': billings.aggregate(total=Sum('net_due'))['total'] or Decimal('0.00'),
        'collected': payments.aggregate(total=Sum('amount'))['total'] or Decimal('0.00'),
    }


# --- Retention ---------------------------------------------------------------


def retention_for(project):
    """Retention withheld on approved billings, less what was released."""
    held = ProgressBilling.objects.filter(
        project=project, status__in=RETENTION_HELD_STATUSES,
    ).aggregate(total=Sum('less_retention'))['total'] or Decimal('0.00')
    released = RetentionRelease.objects.filter(project=project).aggregate(
        total=Sum('amount'),
    )['total'] or Decimal('0.00')
    return {'held': held, 'released': released, 'available': held - released}


def release_retention(user, project, amount, released_on, method, reference_no=''):
    with transaction.atomic():
        project = _locked_project(project)
        _require(rules.can_release_retention(project))
        balance = retention_for(project)['available']
        _require(rules.validate_payment(amount, balance))

        release = RetentionRelease.objects.create(
            project=project, amount=amount, released_on=released_on,
            method=method, reference_no=(reference_no or '').strip(),
        )
        user_services.record(
            user, 'retention_released', 'project', project.pk,
            {'amount': f'{amount:.2f}'},
        )
    return release


# --- Variation orders --------------------------------------------------------


def save_vo(user, project, payload, priced_by_owner, vo=None):
    """Create (`vo is None`) or edit a **proposed** variation order.

    A site engineer proposes the change and never prices it: the amount is
    stored as `0.00` for a new VO, and an existing amount is left untouched.
    """
    description = str(payload.get('description') or '').strip()
    _require(rules.validate_vo_description(description))
    vo_type = payload.get('type') or (vo.type if vo else None)
    days_impact = payload.get('days_impact', vo.days_impact if vo else 0)
    repriced = priced_by_owner and 'amount' in payload

    with transaction.atomic():
        project = _locked_project(project)
        total_billed = billing_math.previous_gross(project)

        if vo is None:
            amount = (
                rules.signed_amount(vo_type, payload['amount'])
                if priced_by_owner else Decimal('0.00')
            )
        else:
            vo = VariationOrder.objects.select_for_update().get(pk=vo.pk)
            if vo.status != VariationOrderStatus.PROPOSED:
                _refuse(rules.VO_EDIT_PROPOSED)
            amount = (
                rules.signed_amount(vo_type, payload['amount'])
                if repriced else vo.amount
            )

        if vo is None and priced_by_owner:
            _require(rules.validate_vo_amount(vo_type, payload.get('amount')))
        if repriced:
            _require(rules.validate_vo_amount(vo_type, payload['amount']))
        _require(rules.validate_contract_after_vo(
            project.contract_amount, amount, total_billed,
        ))

        if vo is None:
            count = VariationOrder.objects.filter(project=project).count()
            vo = VariationOrder.objects.create(
                project=project,
                vo_no=f'VO-{count + 1:02d}' if count else 'VO-01',
                type=vo_type,
                description=description,
                amount=amount,
                days_impact=days_impact,
                status=VariationOrderStatus.PROPOSED,
            )
            user_services.record(user, 'vo_proposed', 'variation_order', vo.pk)
            if not priced_by_owner:
                _tell(
                    project, RoleOnProject.OWNER, 'variation_order',
                    f'{vo.vo_no} was proposed for {project.code}. Prepare it.',
                    f'/variation-orders/{vo.pk}',
                )
        else:
            vo.type = vo_type
            vo.description = description
            vo.amount = amount
            vo.days_impact = days_impact
            vo.save(update_fields=['type', 'description', 'amount',
                                   'days_impact', 'updated_at'])
            user_services.record(user, 'vo_updated', 'variation_order', vo.pk)
    return vo


def _locked_vo(vo):
    return VariationOrder.objects.select_for_update().get(pk=vo.pk)


def submit_vo(user, vo):
    with transaction.atomic():
        vo = _locked_vo(vo)
        if vo.status != VariationOrderStatus.PROPOSED:
            _refuse(rules.VO_SUBMIT_PROPOSED)
        if rules.validate_vo_amount(vo.type, abs(vo.amount)) is not None:
            _refuse(rules.VO_PRICE_REQUIRED)
        vo.status = VariationOrderStatus.PENDING_CLIENT
        vo.approved_by_owner = user
        vo.save(update_fields=['status', 'approved_by_owner', 'updated_at'])
        user_services.record(user, 'vo_submitted', 'variation_order', vo.pk)
        _tell(
            vo.project, RoleOnProject.CLIENT, 'variation_order',
            f'{vo.vo_no} is waiting for your approval.',
            f'/client/variation-orders/{vo.pk}',
        )
    return vo


def owner_reject_vo(user, vo, reason):
    _require(rules.REASON if not str(reason or '').strip() else None)
    with transaction.atomic():
        vo = _locked_vo(vo)
        if vo.status != VariationOrderStatus.PROPOSED:
            _refuse(rules.VO_REJECT_PROPOSED)
        vo.status = VariationOrderStatus.REJECTED
        vo.save(update_fields=['status', 'updated_at'])
        user_services.record(user, 'vo_owner_rejected', 'variation_order', vo.pk,
                             {'reason': reason.strip()})
    return vo


def client_approve_vo(user, vo):
    """Apply an approved VO to the contract amount and target end date, once.

    The **project** row is locked first, then the VO row — the same order as
    `save_vo`, so a concurrent owner edit cannot deadlock against this approval.
    The status check, the contract-after-VO check, the project update and the
    audit row are one transaction, so a double approval cannot apply the money
    twice.
    """
    with transaction.atomic():
        project = Project.objects.select_for_update().get(pk=vo.project_id)
        vo = _locked_vo(vo)
        if vo.status != VariationOrderStatus.PENDING_CLIENT:
            _refuse(rules.VO_NOT_WAITING)
        _require(rules.validate_contract_after_vo(
            project.contract_amount, vo.amount,
            billing_math.previous_gross(project),
        ))

        vo.status = VariationOrderStatus.APPROVED
        vo.approved_by_client = user
        vo.save(update_fields=['status', 'approved_by_client', 'updated_at'])

        project.contract_amount = project.contract_amount + vo.amount
        if project.target_end_date is not None:
            project.target_end_date = (
                project.target_end_date + timezone.timedelta(days=vo.days_impact)
            )
        project.save(update_fields=['contract_amount', 'target_end_date', 'updated_at'])
        user_services.record(user, 'vo_client_approved', 'variation_order', vo.pk)
        _tell(
            project, RoleOnProject.OWNER, 'variation_order',
            f'{vo.vo_no} is approved. The contract amount and target end date '
            'are updated; adjust categories and to-dos.',
            f'/variation-orders/{vo.pk}',
        )
    return vo


def client_reject_vo(user, vo, reason):
    _require(rules.REASON if not str(reason or '').strip() else None)
    with transaction.atomic():
        vo = _locked_vo(vo)
        if vo.status != VariationOrderStatus.PENDING_CLIENT:
            _refuse(rules.VO_NOT_WAITING)
        vo.status = VariationOrderStatus.REJECTED
        vo.save(update_fields=['status', 'updated_at'])
        user_services.record(user, 'vo_client_rejected', 'variation_order', vo.pk,
                             {'reason': reason.strip()})
    return vo


# --- Read helpers ------------------------------------------------------------

def billings_for(project_queryset, project=None, status=None):
    queryset = ProgressBilling.objects.filter(
        project__in=project_queryset,
    ).select_related('project')
    if project is not None:
        queryset = queryset.filter(project=project)
    if status:
        queryset = queryset.filter(status=status)
    return queryset


def vo_for(project_queryset, project=None, status=None):
    queryset = VariationOrder.objects.filter(
        project__in=project_queryset,
    ).select_related('project')
    if project is not None:
        queryset = queryset.filter(project=project)
    if status:
        queryset = queryset.filter(status=status)
    return queryset


def payments_for(project_queryset):
    """Client payments of the given projects, newest paid-on first."""
    return ClientPayment.objects.filter(
        progress_billing__project__in=project_queryset,
    ).select_related('progress_billing')


def history(entity, entity_id):
    """The audit trail of one row, newest first (the client portal's history)."""
    from ..users.models import AuditLog

    return AuditLog.objects.filter(entity=entity, entity_id=entity_id)
