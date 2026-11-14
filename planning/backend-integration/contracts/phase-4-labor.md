# Phase 4 labor contract — slice A: workers and attendance

Status: implementation brief; delegated, revisable defaults, not separately owner-confirmed payroll policy. Baseline: operational procurement commit `7747973`.

## Boundary

Build workers and project-scoped attendance independently of blocked procurement accounting. No payroll calculation/processing, deductions, periods, aggregate expense posting or HTTP labor repository in this slice. Do not claim completed labor integration until later slices implement those repository methods and verification.

Authoritative frontend shapes: `flutter/lib/data/models/{worker,attendance}.dart`, `data/repositories/labor_repository.dart`, `data/services/labor_rules.dart`. Existing backend active-role and accepted-project-assignment rules remain authoritative; do not copy mock authorization.

## Routes and wire shapes

- `GET /api/v1/workers/?active_only=true`: company-wide staff picker, deterministic ordering; normal house pagination.
- `POST /api/v1/workers/`, `PATCH /api/v1/workers/{id}/`: create/update worker; no DELETE.
- `GET /api/v1/attendance/?project=ID&from=YYYY-MM-DD&to=YYYY-MM-DD`: project required; dates optional inclusive filters, malformed/reversed bounds refused.
- `POST /api/v1/attendance/save-day/`: `{project_id, work_date, entries:[{worker_id,status,overtime_hours}]}`. Return saved attendance rows using house list convention, no confidential worker fields.

Worker finance response: `id, full_name, trade, daily_rate, sss_no, philhealth_no, pagibig_no, is_active, created_at, updated_at`. `trade` is the Trade's name, not numeric ID. Non-finance responses OMIT daily_rate and all government identifier keys; absence is not authoritative zero. HTTP worker adapter/hidden-rate UI handling is a later required slice, not automatically usable with the existing zero-default decoder.

Attendance response: `id, project_id, worker_id, work_date, status, overtime_hours, recorded_by, created_at, updated_at`. Actor/timestamps/IDs server-owned; caller must not set recorded_by or bypass scope through project_id on generic CRUD. No unrestricted generic attendance writes.

## Permissions and delegated defaults

- Resolve validated active role via existing capabilities helpers. Never union held roles for CPMS authorization.
- Client denied every labor endpoint. Other staff may read minimal company-wide worker picker.
- Owner/accountant may maintain workers company-wide, matching existing editor workflow. Active admin/site engineer cannot see or write wages/identifiers; do not broaden admin finance privileges.
- Staff attendance reads use `projects_for`/`project_or_404`; unrelated or pending/declined assignments grant nothing.
- Attendance writes require active site_engineer and accepted site_engineer assignment to the project; holding that role while acting as another is insufficient.
- Worker names and rates validated (positive finite Decimal rate, representable precision); trim nonempty full_name; booleans strictly parsed. Trade resolves existing master name, protected FK. Refuse protected Trade deletion cleanly rather than return 500.
- Worker histories are retained: no hard delete. Inactive workers cannot receive new attendance entries; an existing row may be corrected without reactivating the worker. Every ordinary staff picker can still read historical worker identity with active_only=false.
- Write audit records atomically, with no wages, government IDs or sensitive raw payload in broadly visible details. Notifications only if existing pattern calls for them; no new notification scheme.

## Attendance rules and concurrency

- Status: present, half_day, absent. Reject unknown values and duplicate worker IDs.
- Date cannot be in the future using server Manila date. Validate strict ISO dates.
- Overtime finite Decimal 0–12; absent stores zero after validating numeric range. Do not accept NaN/Infinity/booleans as numbers.
- Atomic partial-sheet upsert: entries replace listed workers only, omitted workers unchanged, empty entries no-op. Any invalid entry refuses the entire save, including audits.
- One row per (project, worker, work_date). Worker cannot have non-absent attendance at different projects on the same date (even two half-days); absence at another project is allowed.
- Enforce database uniqueness plus stable worker lock ordering to serialize competing cross-project saves; map races to clean validation errors, never 500 or partial saves.
- No payroll tables exist in this slice. Before later payroll processing ships, add processed-period attendance locks and verification invalidation for changed verified attendance in the SAME dependent rollout. Do not present slice A as payroll-ready on its own.

## Required focused tests

Active-role fences, accepted-assignment scoping/IDOR, client denial, wage/identifier redaction and audit non-leakage; create/update/positive finite rates and Trade protection; attendance atomic partial save, empty no-op, duplicate workers, missing IDs, inactive new-entry refusal and historical correction, future dates, inclusive query filters, overtime bounds/nonfinite rejection/absent normalization; cross-project presence conflicts and at least one true concurrent save pin using isolated PostgreSQL.

Only `cpms_test_backend` / `cpms_test_db` disposable stack; serialize CPMS backend suites. No live/dev database migrations, POS mutations, commits or pushes during building.

## Next slices / unresolved production policy

Payroll periods, previews, advances, processing and HTTP/UI integration follow separately. Existing frontend payroll calculator uses simplified statutory percentages; production processing requires authoritative contribution/cap/frequency policy. Do not invent statutory deductions or label demo parity legally compliant. Negative-net handling and multi-project/period deductions remain unresolved. POS valuation/debt-ownership blockers remain untouched.
