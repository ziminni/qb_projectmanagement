"""Refusal texts and numeric rules for procurement (Phase 3, task 3.1a).

Every message quoted from the Flutter mock is the mock's own text; texts marked
*new* had no mock equivalent and are listed in the contract's
"3.1a Built as" section.

Raised as the Phase 2 exceptions so views stay thin and the wire shape matches:

    RuleRefused      -> 400 {"detail": "<mock text>"}
    NotAllowed       -> 403 {"detail": "<mock text>"}
    StaleSiteCount   -> 409 {"detail": "...", "code": "STALE_SITE_COUNT"}

Out-of-scope objects stay a `404` raised by `apps.projects.scoping`.
"""

from decimal import Decimal, InvalidOperation

from rest_framework.exceptions import APIException

from ..projects.rules import NotAllowed, RuleRefused  # re-exported for views
from ..users.models import Role

__all__ = [
    'NotAllowed', 'RuleRefused', 'StaleSiteCount', 'as_decimal', 'as_quantity',
    'as_money', 'as_count',
]

# At most 2 decimal places and these bounds: quantities are Decimal(12,2) —
# the POS import refuses anything under 0.01 or over 9999999999.99 anyway.
QUANTITY_PLACES = Decimal('0.01')
QUANTITY_MAX = Decimal('9999999999.99')
MONEY_MAX = Decimal('9999999999.99')


class StaleSiteCount(APIException):
    """409 — the submitted site counts disagree with the server's snapshot."""

    status_code = 409
    default_code = 'STALE_SITE_COUNT'

    def __init__(self):
        super().__init__(
            detail={
                'detail': STALE_COUNT,
                'code': 'STALE_SITE_COUNT',
            }
        )


# --- material requests (mock texts) --------------------------------------
NOT_THE_ENGINEER = (
    'Only the site engineer assigned to this project can request materials.'
)
ADD_AN_ITEM = 'Add at least one item.'
ENTER_ITEM = 'Enter the item.'
QUANTITY_POSITIVE = 'Quantity must be greater than 0.'
NEEDED_BY_REQUIRED = 'Choose the needed-by date.'
NEEDED_BY_PAST = 'The needed-by date cannot be in the past.'
REJECT_REASON = 'Give a reason for rejecting.'
COUNT_INVALID = 'Enter the count (0 or more).'

# --- purchase orders (mock texts) ---------------------------------------
REQUEST_REJECTED = 'This request was rejected.'
NOT_THE_PM = 'Only the owner running this project can approve this.'
CHOOSE_CATEGORY = 'Choose the budget category of this project.'
ADD_A_MATERIAL = 'Add at least one material.'
NOT_ON_REQUEST = 'An item is not on this request.'
ENTER_MATERIAL = 'Enter the material.'
UNIT_PRICE = 'Enter a unit price of 0 or more.'
DELIVERY_ADDRESS = 'Enter the delivery address.'
OWN_STORE_CATALOG = 'Pick own-store materials from the store catalog.'
NO_OWN_STORE = 'Set up the own store in the supplier list first.'
ENTER_STORE_NAME = 'Enter the store name.'
ENTER_OR_NUMBER = 'Enter the OR number.'
ATTACH_RECEIPT = 'Attach a photo of the receipt.'
PO_HAS_DELIVERIES = 'A PO with deliveries cannot be cancelled.'
PAID_AT_STORE = 'A purchase already paid at the store cannot be cancelled.'

# --- deliveries (mock texts) -------------------------------------------
NOT_THE_SE = 'Only the site engineer on this project confirms its deliveries.'
ENTER_RECEIVED = 'Enter the quantity received.'
UNKNOWN_PO_LINE = 'Unknown PO line.'
NEGATIVE_QUANTITY = 'Quantities cannot be negative.'
DAMAGED_GT_RECEIVED = 'Damaged cannot exceed received.'

# --- 3.1a-only texts (no mock equivalent) ------------------------------
CLIENT_NO_PROCUREMENT = 'Only the project team can see procurement records.'
NOT_FINANCE_BUDGET = "Only the project's owner or accountant can check a budget."
AMOUNT_REQUIRED = 'Enter the amount to check.'
AMOUNT_INVALID = 'Enter an amount of 0 or more.'
PRECISION = 'Use at most 2 decimal places.'
TOO_LARGE = 'That number is too large.'
BAD_LINES = 'The order lines could not be read.'
DUPLICATE_PO_LINE = 'Each PO line can be received once per delivery.'
AMBIGUOUS_OWN_STORE = 'More than one own store is set up. Keep exactly one.'
MISSING_POS_CODE = (
    'A material has no POS code yet. Map it in the price list before ordering '
    'from the own store.'
)
STALE_COUNT = 'The site count changed. Refresh and count again.'
COUNT_MATERIAL = 'Pick the counted material from the price list or leave it blank.'

# Flutter `AppRole.label`, lower-cased inside the mock's own sentence.
ROLE_LABELS = {
    Role.ADMIN: 'System admin',
    Role.OWNER: 'Owner / Project manager',
    Role.SITE_ENGINEER: 'Site engineer / foreman',
    Role.ACCOUNTANT: 'Accountant / finance',
    Role.CLIENT: 'Client',
}


def cannot_reject(status_label, role):
    """The mock's reject refusal, in its exact sentence."""
    label = ROLE_LABELS.get(role, str(role)).lower()
    return (
        f'This request is {status_label.lower()} and cannot be rejected by a '
        f'{label}.'
    )


def count_first(name):
    return f'Count the {name} on site before requesting more.'


def already_covered(description):
    return f'{description} is already covered by another order.'


def nothing_to_receive(status_label):
    return f'This PO is {status_label.lower()}; there is nothing to receive.'


def only_left(left):
    """`Only 4 left to receive on this line.` (mock `_q` formatting)."""
    number = Decimal(left)
    text = (
        f'{number:.0f}' if number == number.to_integral_value()
        else f'{number:.2f}'
    )
    return f'Only {text} left to receive on this line.'


def _decimal(value):
    """Parse a JSON number/string; `None` for junk, booleans and non-finite."""
    if isinstance(value, bool):
        return None
    try:
        number = Decimal(str(value).strip())
    except (InvalidOperation, TypeError, ValueError):
        return None
    return number if number.is_finite() else None


def _excess_precision(number):
    return number != number.quantize(QUANTITY_PLACES)


def as_quantity(value):
    """A `Decimal(12,2)` quantity, or `None` when it cannot be one.

    Refuses junk, booleans, NaN/±Infinity, excess decimal places (never
    silently rounds) and anything above the 12,2 maximum.
    """
    number = _decimal(value)
    if number is None or _excess_precision(number):
        return None
    if number < 0 or number > QUANTITY_MAX:
        return None
    return number


def as_money(value, maximum=MONEY_MAX):
    """A non-negative money amount with at most 2 decimal places, or `None`."""
    number = _decimal(value)
    if number is None or _excess_precision(number):
        return None
    if number < 0 or number > maximum:
        return None
    return number


def as_count(value):
    """A counted quantity: a `Decimal(12,2)`, zero or more."""
    return as_quantity(value)


def as_decimal(value):
    """Any finite decimal (used for the advisory `?amount=` query value)."""
    return _decimal(value)
