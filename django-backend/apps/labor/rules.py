"""Refusal texts for the labor slice.

Every message is raised as a DRF `400 {"detail": "<text>"}` through
`apps.projects.rules.RuleRefused`, or a `403` through `NotAllowed`. Texts that
exist in the Flutter mock (`mock_labor_repository.dart`) are reused verbatim;
the rest are proposed for this backend slice.
"""

# Workers.
WORKER_NAME = "Enter the worker's name."
WORKER_TRADE = "Choose the worker's trade."
TRADE_IN_USE = 'This trade is used by workers and cannot be deleted.'
RATE_POSITIVE = 'Daily rate must be greater than 0.'
RATE_INVALID = 'Enter the daily rate as a number.'
RATE_PRECISION = 'Use at most 2 decimal places.'
STAFF_ONLY = 'Staff role required.'
WORKER_MAINTENANCE = 'Project Manager or Accountant role required to change workers.'

# Attendance reads.
PROJECT_REQUIRED = 'Choose a project.'
PROJECT_NOT_FOUND = 'Project not found.'
FILTER_DATE = 'The {name} filter must be a date in YYYY-MM-DD.'
REVERSED_DATES = 'The from date must be on or before the to date.'

# Attendance save-day.
SE_ONLY = 'Only the site engineer on this project records its attendance.'
WORK_DATE_REQUIRED = 'Enter a valid work date in YYYY-MM-DD.'
FUTURE_DATE = 'Attendance cannot be recorded for a future date.'
ENTRY_STATUS = 'Choose present, half day or absent.'
UNKNOWN_WORKER = 'One of the workers was not found.'
DUPLICATE_WORKER = "Each worker can appear only once in a day's sheet."
INACTIVE_WORKER = 'Inactive workers cannot be given new attendance.'
OVERTIME_NEGATIVE = 'Overtime cannot be negative.'
OVERTIME_RANGE = 'Overtime cannot exceed 12 hours a day.'
OVERTIME_INVALID = 'Enter the overtime hours as a number.'
PRESENCE_CONFLICT = '{name} is already marked present on another project that day.'
# The database backstop refused a presence the lock did not see (a race).
PRESENCE_CONFLICT_GENERIC = 'A worker is already marked present on another project that day.'
