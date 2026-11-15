# Phase 4 payroll contract — slice C: periods, advances, processing

Status: **built** on branch `feat/cpms-payroll-periods`. Everything here is a
delegated, revisable default (`../decisions/06-phase-2-contract-rulings.md`
pattern), not owner-confirmed payroll policy. Baseline: labor slice A
(`phase-4-labor.md`, commit `c2bce8c`).

## Boundary

Payroll **periods, verification, cash advances, processing, labor-cost** and the
attendance lock that depends on them. No statutory deduction computation, no
expense posting, no HTTP/UI labor payroll repository (that is 4.3/5.x). The mock
calculator's flat SSS/PhilHealth/Pag-IBIG percentages
(`flutter/lib/data/services/payroll_calculator.dart`) are deliberately **not**
copied.

Authoritative frontend shapes: `flutter/lib/data/models/{payroll_period,
payroll_line}.dart`. Money is a 2-dp string, dates `YYYY-MM-DD`.

## Routes and wire shapes

All under `/api/v1/`.

| Route | Method | Who |
|---|---|---|
| `payroll-periods/` | GET (list, `?project=ID` filter) | any staff role, scoped |
| `payroll-periods/{id}/` | GET | any staff role, scoped |
| `payroll-periods/` | POST `{project_id, period_start, period_end}` | accountant |
| `payroll-periods/{id}/verify/` | POST | accepted project owner |
| `payroll-periods/{id}/cash-advance/` | POST `{worker_id, amount}` | accountant |
| `payroll-periods/{id}/lines/` | GET | finance (owner, accountant) |
| `payroll-periods/{id}/process/` | POST | accountant |
| `labor-cost/?project=ID` | GET | finance (owner, accountant) |

Period response: `id, project_id, period_start, period_end, status,
created_at, updated_at` (all server-owned; `status` is `open|verified|
processed`).

Line response: `id, payroll_period_id, worker_id, days_worked, overtime_pay,
gross_pay, cash_advance, statutory_deductions, deductions_policy, net_pay`. A
line computed before processing carries `id: 0`; only a processed line has a
stored id.

Refusals are `400 {"detail": "<sentence>"}` with the mock's wording where it
exists (`flutter/lib/data/services/labor_rules.dart`), `403` for a wrong active
role, `404` for out-of-scope/missing project or period.

## Permissions (delegated defaults)

- The **active role** decides, never the union of held roles
  (`capabilities.active_role`). Scope is checked first, so an unassigned owner
  gets `404`, not `403`.
- Period rows are readable by every staff role (a site engineer needs the
  cut-off calendar); the client portal is refused (`403`).
- **Accountant only**: create periods, move cash advances, process.
- **Accepted owner of the project only**: verify attendance.
- **Finance only** (`sees_finance`: owner, accountant): `lines/` and
  `labor-cost/`. Site engineer and admin never receive wages.
- Refused writes leave no row, no audit and no half-applied money: each write is
  one `transaction.atomic()` with its audit row.
- Audits (`payroll_period_created`, `attendance_verified`,
  `payroll_advance_set`, `payroll_processed`, `payroll_reopened`) carry only
  project code, period dates and (where relevant) `worker_id`, `lines`, `reason`,
  `work_date` — never an amount, a rate or a total.

## Period rules

- `period_end >= period_start`; the span is **inclusive** and at most **16
  days** (`(end - start).days + 1 <= 16`) — "a week or 15 days, not more than
  16". Strict ISO dates only.
- Overlapping periods for the same project are refused (inclusive overlap test
  under the project row lock); the DB unique `(project, period_start)` is the
  backstop for simultaneous creates. Different projects may overlap freely.
- State machine: `open → verified → processed`, plus one step back:
  **changed attendance on a verified period reopens it** (`verified → open`).
  `processed` is terminal — no route moves a processed period.
- Verification requires an open period whose **cut-off has been reached**
  (server Manila date `>= period_end`), and records `attendance_verified`.
- Any changed attendance entry inside a **verified** period reopens it and
  audits `payroll_reopened` (`reason: attendance_changed`, the `work_date`). A
  save that does not change the row keeps the period verified.

## Pay arithmetic (delegated defaults)

- Day fractions: `present = 1.00`, `half_day = 0.50`, `absent = 0.00`.
- `hourly = daily_rate / 8`; overtime premium **1.25** (Labor Code regular-day
  premium, a revisable default).
- `overtime_pay = money(hours * hourly * 1.25)`, then `gross_pay =
  money(daily_rate * days + overtime_pay)`; `net_pay = gross_pay -
  cash_advance - statutory_deductions`. `money()` quantizes to centavos
  **half-up** (the mock's rounding order: overtime is rounded before it enters
  gross). Checked against the mock: 1 day present + 1 half day + 2 OT hours at
  750.00/day → gross `1359.38`, overtime `234.38`.

## Cash advances

- One advance per `(period, worker)`, set (upserted) or reset to `0.00`; never
  deleted, so the history is kept. `0 <= amount <= that worker's gross pay for
  the period`; a worker with no attendance in the period is refused; a
  processed period is refused.
- The bound is re-applied at **process** time against the recomputed gross:
  correcting a verified day (or raising `daily_rate`) can shrink gross under a
  stored advance, and issuing a negative net is refused (`400`, the same
  "Cash advance cannot exceed gross pay." text as the set-time rule). The
  accountant lowers the advance and processes — the period is open again after
  any such correction. No DB `net_pay >= 0` check exists: with statutory
  deductions unconfigured, this service-level refusal is the whole invariant
  (see open policies).

## Processing and attendance lock

- Processing requires a verified period; it snapshots one `PayrollLine` per
  worker with attendance into stored rows, then marks the period processed. A
  second process is refused (`400`, `409` race mapped to the same text). A line
  is a snapshot: a later wage change never rewrites issued pay.
- Attendance in a **processed** period is locked (`save-day` → `400` "Attendance
  in a processed payroll period is locked.").
- Lock order is fixed and shared by process and `save-day`:
  **project row → period row → rows being written**. That makes "process vs.
  save attendance" a real serialization: whoever wins forces the other to
  refuse (processed) or see the new attendance before snapshotting. The race
  test asserts both legal outcomes.
- `labor-cost/?project=ID` is the gross pay of **processed** lines only; it is
  not posted to the expense log (payroll accounting policy is still open).

## Deductions placeholder

Every line carries `deductions_policy = 'unconfigured'` and
`statutory_deductions = 0.00`. No SSS/PhilHealth/Pag-IBIG/withholding table,
cap or percentage is computed, and demo percentages are never presented as
compliant payroll.

## Open owner policies (not built, not invented)

1. **Statutory deductions**: contribution tables, wage caps and frequency
   (semi-monthly vs. monthly cut-offs), employee vs. employer share, and
   rounding of each contribution. Needed before `deductions_policy` can leave
   `'unconfigured'`.
2. **Negative-net handling** once such a policy exists: carry over, refuse, or
   cap the deduction. Today only advances can shrink net and they are refused
   when they would go below zero.
3. **Multi-project / multi-period deductions**: a worker on two projects (or in
   adjacent periods of one cut-off) must not pay statutory caps twice; the
   aggregation unit (company-wide per month) is undecided.
4. **Payroll accounting**: whether processed gross becomes an expense/ledger
   entry and when, and how payroll feeds derived `ProjectCosts`.
5. **Period cadence**: only the 16-day inclusive cap is enforced; weekly vs.
   15-day vs. semi-monthly project convention is not.

## Required focused tests

`django-backend/apps/labor/tests_payroll.py` covers every rule above: active-role
fences, scoping/IDOR, period validation and overlap, verification at cut-off,
computed lines and the deduction placeholder, advance bounds (including a stale
advance above a recomputed gross → process refused, then lowered and processed),
processed-period attendance lock, verification invalidation, labor cost, audits
without wages, and one real process-vs-save race on PostgreSQL.

Only the disposable `cpms_test_backend` / `cpms_test_db` stack; serialize CPMS
backend suites. No live/dev database migrations, commits or pushes while
building.
