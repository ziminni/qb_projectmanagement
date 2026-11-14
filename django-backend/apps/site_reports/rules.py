"""Refusal texts and rules for daily reports, documents and uploads.

Texts are the Flutter mock's, quoted from
`lib/data/services/{daily_report_rules,project_rules}.dart` and
`repositories/mock_{daily_report,document}_repository.dart`. Texts marked
*proposed* in `planning/backend-integration/contracts/phase-2-projects-and-site.md`
are marked here too; the rest of the 2.2-only texts (nested ids, signatures,
size caps, photo author) are new and listed in the session report.
"""

from decimal import Decimal, InvalidOperation

from .models import DailyReportStatus, DocumentType


def _can_edit_message(status):
    label = DailyReportStatus(status).label.lower()
    return f'This report is {label} and can no longer be edited.'


# --- daily reports (mock texts) -------------------------------------------
NOT_THE_ENGINEER = (
    'Only the site engineer assigned to this project can file its reports.'
)
NOT_THE_AUTHOR_SUBMIT = 'Only the site engineer who wrote this report can submit it.'
NOT_THE_OWNER_REVIEW = 'Only the owner of this project can review its reports.'
REPORTS_STAFF_ONLY = 'Only the project team can see the site reports.'
CANNOT_SUBMIT = 'Only draft or returned reports can be submitted.'
CANNOT_REVIEW = 'Only submitted reports can be approved or returned.'
RETURN_REMARKS = 'Add remarks so the site engineer knows what to fix.'

# --- daily reports (2.2-only texts) ---------------------------------------
NOT_THE_AUTHOR_EDIT = 'Only the site engineer who wrote this report can edit it.'
NOT_THE_AUTHOR_PHOTO = (
    'Only the site engineer who wrote this report can change its photos.'
)
CHOOSE_MATERIAL = 'Choose a material from the list.'
CHOOSE_EQUIPMENT = 'Choose a piece of equipment from the list.'
CHOOSE_TODO = 'Choose a to-do from this project.'
CHOOSE_WEATHER = 'Choose the weather.'
CHOOSE_ISSUE_TYPE = 'Choose the type of each issue.'
CHOOSE_ISSUE_REASON = 'Choose the reason for each issue.'

# --- documents (mock texts) -----------------------------------------------
NOT_AN_UPLOADER = "Only the project's owner or site engineer can upload."
NOT_A_DELETER = 'Only the uploader or the owner can delete this document.'
DOCUMENT_NAME_REQUIRED = 'Enter the document name.'
DUPLICATE_DOCUMENT = 'A document with this name already exists in this section.'

# --- documents (proposed in the contract / new) ---------------------------
NOT_A_CONTRACT_FILER = 'Only the owner or accountant can file contracts.'
DOCUMENTS_STAFF_ONLY = 'Only the project team can see its documents.'
CHOOSE_SECTION = 'Choose a document section.'
NAME_NOT_ALLOWED = 'The file name is not allowed.'
UPLOAD_FAILED = 'The file could not be read.'


def document_type_refusal(extension_list):
    """The mock's "Choose a file of type ..." text, built from the list."""
    return f'Choose a file of type {", ".join(extension_list)}.'


def signature_refusal(extension):
    return f'The file does not look like a {extension} file.'


def size_refusal(megabytes):
    return f'The file is larger than {megabytes} MB.'


# --- shared parsing -------------------------------------------------------

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


def as_int(value):
    """Parse a JSON integer or integer string; None when it is neither."""
    if isinstance(value, bool):
        return None
    try:
        return int(str(value))
    except (TypeError, ValueError):
        return None


def document_type(value):
    """The `doc_type` code, or None when it is not a section we serve."""
    return value if value in DocumentType.values else None
