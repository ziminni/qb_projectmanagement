"""Billing and variation-order rules, mirroring `billing_rules.dart`.

Every text below is the one the Flutter mock shows the user
(`data/repositories/mock_billing_repository.dart` + `data/services/billing_rules.dart`),
so the desktop client can print it verbatim as a `400 {"detail": ...}` refusal
without a mapping table.

The rules are pure functions of plain values: `None` means allowed, a string is
the refusal text. Nothing here writes.
"""

from decimal import Decimal

from ..projects.models import ProjectStatus
from .models import VariationOrderType

# --- Billing -----------------------------------------------------------------

BILLABLE = (
    'Billings can be prepared only for Ongoing or Completed projects '
    '(this one is {status}).'
)
BILLABLE_STATUSES = (ProjectStatus.ONGOING, ProjectStatus.COMPLETED)

PERIOD_REQUIRED = 'Choose the period end date.'
PERIOD_FUTURE = 'The period end cannot be in the future.'
PERIOD_AFTER_PREVIOUS = "The period must end after the previous billing's period."

ACCOMPLISHMENT_MAX = 'Cumulative accomplishment cannot exceed 100%.'
NO_NEW_WORK = 'There is no new verified accomplishment since the last billing.'

IN_PROGRESS = (
    'This project already has a billing in progress. It must be paid or '
    'rejected first.'
)
ONLY_DRAFT_SUBMITTED = 'Only draft or disputed billings can be submitted.'
ONLY_DRAFT_WITHDRAWN = 'Only draft or disputed billings can be withdrawn.'
# `_expect`: "This billing is draft, not waiting for client."
EXPECT_PENDING_CLIENT = 'This billing is {current}, not waiting for client.'
ONLY_PENDING_ACTIONS = 'Only a billing waiting for the client can be answered.'

PAYMENT_APPROVED_ONLY = 'Payments are recorded only on client-approved billings.'
PAYMENT_POSITIVE = 'Enter an amount greater than 0.'
PAYMENT_OVER = 'The payment exceeds the balance of ₱{balance}.'
PAYMENT_INVALID = 'Enter the amount as a number.'
PAYMENT_DATE_FUTURE = 'The payment date cannot be in the future.'
METHOD_INVALID = 'Choose the payment method.'
RELEASE_DATE_REQUIRED = 'Choose the release date as YYYY-MM-DD.'
REASON = 'Give a reason.'

# --- Retention ---------------------------------------------------------------

RETENTION_RELEASE_STATUSES = (ProjectStatus.COMPLETED, ProjectStatus.CLOSED)
RETENTION_NOT_COMPLETE = 'Retention is released only after the project is Completed.'

# --- Variation orders --------------------------------------------------------

VO_DESCRIPTION = 'Describe the change.'
VO_AMOUNT_REQUIRED = 'Enter the cost impact.'
VO_AMOUNT_POSITIVE = 'Enter an amount greater than 0.'
VO_PRICE_REQUIRED = 'Enter the cost impact before sending the VO to the client.'
VO_BELOW_BILLED = (
    'This would reduce the contract below the ₱{billed} already billed.'
)
VO_NOT_WAITING = 'This VO is not waiting for the client.'
VO_EDIT_PROPOSED = 'Only proposed VOs can be edited.'
VO_SUBMIT_PROPOSED = 'Only proposed VOs can be submitted.'
VO_REJECT_PROPOSED = 'Only proposed VOs can be rejected.'
VO_AMOUNT_INVALID = 'Enter the cost impact as a number.'
VO_DAYS_INVALID = 'Enter the days of impact as a whole number.'
VO_TYPE_INVALID = 'Choose added work, deleted work or a design change.'

# --- Role refusals (403) -----------------------------------------------------

OWNER_PREPARES = 'Only the owner / project manager of this project can do this.'
OWNER_PRICING = 'Only the owner of this project can price or send a VO.'
SE_OR_OWNER_PROPOSES = 'Only the owner or site engineer of this project can raise a VO.'
FINANCE_ONLY = 'Owner or Accountant role required.'
CLIENT_ONLY = 'Only the client of this project can do this.'
VO_SURFACE = 'Owner, site engineer or client role required.'

# --- Lookups -----------------------------------------------------------------

PROJECT_NOT_FOUND = 'Project not found.'
BILLING_NOT_FOUND = 'Billing not found.'
VO_NOT_FOUND = 'Variation order not found.'
PROJECT_REQUIRED = 'Choose a project.'

# Money comparison tolerance is exact on 2-dp values: the mock compared doubles
# with a 0.005 epsilon, which cannot happen with Decimals.
TOLERANCE = Decimal('0.00')


def require_billable(project):
    """Billings are allowed once a project is Ongoing (and for the final one)."""
    if project.status in BILLABLE_STATUSES:
        return None
    return BILLABLE.format(status=project.get_status_display())


def validate_period_end(period_end, today, previous_period_end):
    if period_end is None:
        return PERIOD_REQUIRED
    if period_end > today:
        return PERIOD_FUTURE
    if previous_period_end is not None and period_end <= previous_period_end:
        return PERIOD_AFTER_PREVIOUS
    return None


def validate_accomplishment(pct, this_period):
    """Cumulative accomplishment ≤ 100 % and a billing needs new verified work."""
    if pct > 1:
        return ACCOMPLISHMENT_MAX
    if this_period <= Decimal('0.005'):
        return NO_NEW_WORK
    return None


# `net_due = this_period - dp - retention`, so a split of 100 % or more leaves a
# billing that can never be paid while it blocks the project as in-progress.
PCT_BURDEN = (
    'The down payment and retention percentages add up to 100% or more, so this '
    'billing would have nothing left to pay. Adjust the project percentages first.'
)


def validate_pct_burden(down_payment_pct, retention_pct):
    """Refuse a project whose DP + retention leaves no payable net due."""
    if down_payment_pct + retention_pct >= 100:
        return PCT_BURDEN
    return None


def validate_payment(amount, balance):
    if amount is None or amount <= 0:
        return PAYMENT_POSITIVE
    if amount > balance + TOLERANCE:
        return PAYMENT_OVER.format(balance=f'{balance:.2f}')
    return None


def can_release_retention(project):
    if project.status in RETENTION_RELEASE_STATUSES:
        return None
    return RETENTION_NOT_COMPLETE


def validate_vo_description(description):
    if not str(description or '').strip():
        return VO_DESCRIPTION
    return None


def signed_amount(vo_type, amount):
    """Signed cost impact: deleted work reduces the contract."""
    if vo_type == VariationOrderType.DEDUCTIVE:
        return -abs(amount)
    return amount


def validate_vo_amount(vo_type, amount):
    if amount is None:
        return VO_AMOUNT_REQUIRED
    # A design change may be priced at zero; added/deleted work may not.
    if vo_type != VariationOrderType.CHANGE and amount <= 0:
        return VO_AMOUNT_POSITIVE
    return None


def validate_contract_after_vo(contract_amount, vo_amount, total_billed):
    """A VO may not reduce the contract below the amount already billed."""
    if contract_amount + vo_amount < total_billed:
        return VO_BELOW_BILLED.format(billed=f'{total_billed:.2f}')
    return None

