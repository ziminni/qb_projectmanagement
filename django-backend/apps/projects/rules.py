"""Refusal texts and business rules for the project module.

Every message here is the one the Flutter mocks show today, unless it is marked
*proposed* in `planning/backend-integration/contracts/phase-2-projects-and-site.md`
(the mock had no text for it). Raised as DRF exceptions so views stay thin:

    RuleRefused  -> 400 {"detail": "<exact mock text>"}
    NotAllowed   -> 403 {"detail": "<exact mock text>"}

Out-of-scope objects are a 404 raised by `scoping` instead, so no project ever
leaks its existence.
"""

from decimal import Decimal, InvalidOperation

from rest_framework.exceptions import APIException

from .models import ProjectStatus, RequestResponse, RoleOnProject


class RuleRefused(APIException):
    """400 — the request breaks a business rule (the mock's `BusinessRuleException`)."""

    status_code = 400

    def __init__(self, detail):
        super().__init__(detail=str(detail))


class NotAllowed(APIException):
    """403 — the active role may not do this on a project it can see."""

    status_code = 403

    def __init__(self, detail):
        super().__init__(detail=str(detail))


# Flutter `AppRole.label` texts, used inside "does not hold the ... role".
ROLE_LABELS = {
    RoleOnProject.OWNER: 'Owner / Project manager',
    RoleOnProject.SITE_ENGINEER: 'Site engineer / foreman',
    RoleOnProject.CLIENT: 'Client',
}

# ---- Client records (task 5.3) -------------------------------------------------
# Reads stay staff-only (`clients/` feeds the project form); the write fence.
CLIENT_WRITE = 'Project Manager or Admin role required to change this.'
CLIENT_NAME_TAKEN = 'A client with this name already exists.'
CLIENT_NAME_REQUIRED = 'Enter the client name.'
CLIENT_LOGIN_TAKEN = 'That client already has a portal login linked.'
CLIENT_USER_REQUIRED = 'Choose the user to link.'
CLIENT_USER_UNKNOWN = 'That user does not exist.'
# A login is never attached by the plain create/update body.
CLIENT_LINK_SEPARATE = 'Link a portal login with the link route.'
CLIENT_EMAIL = 'Enter a valid email address.'
CLIENT_FIELD_TOO_LONG = 'Use at most {limit} characters for the {label}.'
# `Client` field -> (label, max length) for the optional text columns.
CLIENT_TEXT_FIELDS = {
    'contact_person': ('contact person', 255),
    'phone': ('phone', 32),
    'address': ('address', 1000),
}

# The owner's manual moves (`services/project_rules.dart:39-51`).
NEXT_STATUSES = {
    ProjectStatus.ACCEPTED: [ProjectStatus.ONGOING],
    ProjectStatus.ONGOING: [ProjectStatus.COMPLETED, ProjectStatus.ON_HOLD],
    ProjectStatus.ON_HOLD: [ProjectStatus.ONGOING],
    ProjectStatus.COMPLETED: [ProjectStatus.CLOSED],
}

# Statuses in which the contract amount and the client are frozen (R3, Q4).
WORK_STARTED_STATUSES = frozenset({
    ProjectStatus.ONGOING,
    ProjectStatus.ON_HOLD,
    ProjectStatus.COMPLETED,
    ProjectStatus.CLOSED,
})
# Before the client answers, the owner may still change who the client is.
CLIENT_LOCKED_STATUSES = frozenset(set(ProjectStatus.values) - {
    ProjectStatus.REQUESTED,
    ProjectStatus.CHANGES_REQUESTED,
    ProjectStatus.DECLINED,
})

ANSWERABLE = frozenset({
    RequestResponse.ACCEPTED,
    RequestResponse.DECLINED,
    RequestResponse.CHANGES_REQUESTED,
})


def peso(amount):
    """Format an amount the way the schedule mock does: `₱1,300,000`."""
    return f'₱{Decimal(amount):,.0f}'


def as_decimal(value):
    """Parse a JSON number or numeric string; None when it is neither.

    Non-finite values (`NaN`, `sNaN`, `Infinity`, `-Infinity`) are refused too:
    the JSON parser accepts those literals, `Decimal` parses them, and the first
    `<`/`<=`/`>` comparison then raises `InvalidOperation` (a 500 instead of the
    contract's `400`). `None` lets every existing refusal text fire.
    """
    try:
        number = Decimal(str(value))
    except (InvalidOperation, TypeError, ValueError):
        return None
    return number if number.is_finite() else None


def validate_contract_amount(value):
    amount = as_decimal(value)
    if amount is None:
        return 'Enter the contract amount.'
    if amount <= 0:
        return 'Contract amount must be greater than 0.'
    return None


def validate_dates(start, target_end):
    if start is None or target_end is None:
        return 'Choose the start and target end dates.'
    if target_end <= start:
        return 'Target end date must be after the start date.'
    return None


def validate_percent(value, label):
    """`label` is 'down payment' or 'retention' (mock labels)."""
    percent = as_decimal(value)
    if percent is None:
        return f'Enter the {label}.'
    if percent < 0 or percent > 100:
        return f'The {label} must be 0–100%.'
    return None
