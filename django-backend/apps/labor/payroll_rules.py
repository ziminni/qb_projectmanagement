"""Refusal texts for payroll periods (slice C).

Texts that exist in the Flutter mock (`mock_labor_repository.dart`,
`labor_rules.dart`) are reused verbatim so the desktop screens show the same
sentence; the role texts are proposed for this backend slice.
"""

# Roles.
ACCOUNTANT_ONLY = 'Accountant role required to run payroll.'
OWNER_VERIFIES = 'Only the owner of this project verifies its attendance.'
FINANCE_ONLY = 'Owner or Accountant role required to see payroll.'

# Period create.
PERIOD_DATES = 'Choose the period dates.'
PERIOD_REVERSED = 'The period must end on or after it starts.'
PERIOD_TOO_LONG = 'A payroll period covers a week or 15 days, not more than 16.'
PERIOD_OVERLAP = 'This overlaps an existing payroll period for the project.'

# Verification / processing.
PERIOD_NOT_OPEN = 'This period is not open.'
CUTOFF_NOT_REACHED = (
    'Attendance can be verified once the cut-off date has passed.'
)
NOT_VERIFIED = 'The owner must verify attendance before payroll is processed.'

# Attendance locking (raised by `services.save_day`).
PERIOD_LOCKED = 'Attendance in a processed payroll period is locked.'

# Cash advances.
PERIOD_ALREADY_PROCESSED = 'This period is already processed.'
ADVANCE_NO_ATTENDANCE = 'This worker has no attendance in the period.'
ADVANCE_NEGATIVE = 'Enter 0 or more.'
ADVANCE_OVER_GROSS = 'Cash advance cannot exceed gross pay.'
ADVANCE_INVALID = 'Enter the cash advance as a number.'
