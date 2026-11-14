# Phase 2 wire contract — projects, assignments, schedule, daily reports, documents

**Status:** Draft for Phase 2 build (revisable — update here first if building proves it wrong).
**Source of truth for shapes:** the Flutter models in `flutter/lib/data/models/` (`project.dart`, `project_assignment.dart`, `category.dart`, `todo.dart`, `daily_report.dart`, `report_manpower.dart`, `report_material_usage.dart`, `report_photo.dart`, `equipment_log.dart`, `issue.dart`, `document.dart`) and the interfaces `project_repository.dart`, `schedule_repository.dart`, `daily_report_repository.dart`, `document_repository.dart`. Business rules come from the mocks and `data/services/{project_rules,schedule_rules,daily_report_rules,progress_calculator}.dart`. Backend serves these exact keys; Flutter is not reshaped to fit the backend.

All routes under `/api/v1/`. JSON keys are snake_case. Timestamps ISO-8601 UTC; date-only fields `yyyy-MM-dd`; decimals may be strings (`JsonUtils.toDouble` accepts both, `models/json_utils.dart:4-8`). Active role comes from `X-Active-Role` exactly as in Phase 1; every rule below that names a role means the **active** role, checked through `apps/users/capabilities.py` (`ALL_PROJECTS_ROLES`, `FINANCE_ROLES`, `sees_all_projects()`, `sees_finance()`), never by comparing strings in views.

Citation shorthand: `models/…`, `repositories/…`, `services/…` are under `flutter/lib/data/`; `features/…` is under `flutter/lib/`.

## Error conventions

- Business-rule refusal → `400 {"detail": "<exact mock text>"}`. `HttpXRepository` rethrows `detail` as `BusinessRuleException` / `ScheduleRuleException` so the same text shows as today.
- In scope but the active role may not do it → `403 {"detail": "<exact mock text>"}` (or the proposed text, marked *proposed*, where the mock has none).
- Object outside the caller's project scope → `404 {"detail": "Not found."}`, even where the mock has its own text ("This request is not yours.", "Project not found."). No existence leaks across projects.
- Wrong `X-Active-Role` → Phase 1 `403 {"code": "ROLE_NOT_HELD"}`.

## Project scoping (every project-scoped queryset)

"In scope" = the project is visible to the caller in the active role. Implemented once (e.g. `apps/projects/scoping.py::projects_for(user, role)`) and reused by every viewset, mirroring `repositories/mock_project_repository.dart:41-51`.

| Active role | Projects in scope | Reads | Writes |
|---|---|---|---|
| `admin` | all (`ALL_PROJECTS_ROLES`) | everything except `contract` documents (admin is not a finance role) | user assignments (`users/{id}/assignments/`), unassign. No schedule/report/status writes. |
| `accountant` | all (`ALL_PROJECTS_ROLES`) | everything, incl. finance keys and contracts | none in Phase 2 |
| `owner` (PM) | projects with an **accepted** `owner` assignment for the caller | everything, incl. finance keys | create project; edit/status/resend/team on assigned projects; schedule CRUD; verify/unverify; approve/return reports; upload/delete documents |
| `site_engineer` | projects with an **accepted** `site_engineer` assignment | projects (redacted), schedule (redacted), reports, documents except `contract` | mark to-dos done; daily report drafts/submit; photo + document upload |
| `client` | projects with an **accepted** `client` assignment | portal reads only: own projects (client redaction), categories/to-dos (progress), approved report photos, own pending requests | respond to own request only |

- Pending / `not_sent` / declined / `changes_requested` assignments grant **no** scope (`models/project_assignment.dart:55`, `repositories/project_repository.dart:21-24`). An invitee sees the project only through `project-requests/`.
- Scope is by assignment, not `projects.client_id` (the mock never reads `client_id` for access). See open question Q4.

## Finance redaction (server-side, per active role)

`seesFinance` = `owner`, `accountant` (`models/app_role.dart:19-22`). Redacted keys are **omitted** from the JSON (Phase 1 convention). Non-finance roles writing a redacted key → `400` (cannot set what you cannot see).

| Model.key | owner / accountant | admin | site_engineer | client |
|---|---|---|---|---|
| `Project.contract_amount` | ✔ | omit | omit | ✔ *(their own contract; shown at `features/client_portal/views/client_variation_order_detail_page.dart:113`; Q2)* |
| `Project.down_payment_pct` | ✔ | omit | omit | ✔ *(Q2)* |
| `Project.retention_pct` | ✔ | omit | omit | ✔ *(Q2)* |
| `Category.budget` | ✔ | omit | omit | omit |
| `Document` rows with `doc_type = contract` | ✔ | row hidden | row hidden | no document access (Q5) |

UI evidence for the split: `features/projects/views/project_overview_page.dart:103-131` (contract amount, earned value, down payment, retention only if `seesFinance`), `features/schedule/viewmodels/schedule_viewmodel.dart:64` + `features/schedule/widgets/schedule_category_card.dart:132-137` (budgets), `features/documents/viewmodels/project_documents_viewmodel.dart:46-55` (contracts "carry the contract price").

⚠️ **Blocking for 2.3:** `Project.fromJson` parses `contract_amount`, `down_payment_pct`, `retention_pct` with non-null `JsonUtils.toDouble` (`models/project.dart:77-79`), which throws on a missing key. Omitting them breaks parsing for admin and site engineer. ⚠️ Omitting `budget` makes `computeProjectProgress` fall back to equal weights (`services/progress_calculator.dart:117-118,147-149`), so a site engineer or client sees a **different % accomplished** than the owner. See Q1 and Q3.

No other Phase 2 model carries pesos. Material/equipment rates live on Phase 1.2 masters. Daily-report rows carry only ids, quantities and hours.

## Shapes

- **Project** `{id, code, name, location, latitude, longitude, client_id, contract_amount, down_payment_pct, retention_pct, start_date, target_end_date, actual_end_date, status, created_at, updated_at}`. `status` ∈ `requested, changes_requested, site_engineer_pending, accepted, ongoing, completed, closed, on_hold` (`models/project.dart:3-16`). `client_id` → `clients.id` (a client record, not a user; Q4).
- **ProjectAssignment** `{id, project_id, user_id, role_on_project, response, note, responded_at, created_at, updated_at}`. `role_on_project` ∈ `owner, site_engineer, client` (`services/project_rules.dart:8-12`). `response` ∈ `not_sent, pending, accepted, changes_requested, declined` (`models/project_assignment.dart:6-14`). Always sent (Flutter defaults a missing one to `accepted`, `:79-81`, which must never happen silently).
- **ProjectRequest** (wire wrapper for `repositories/project_repository.dart:6-11`) `{project, assignment}`. `project` is redacted for the invitee's role.
- **Category** `{id, project_id, name, budget, sort_order, created_at, updated_at}`. `budget` is nullable. Progress, status and weight are never stored (`models/category.dart:3-4`).
- **Todo** `{id, category_id, title, start_date, end_date, is_done, done_by, done_at, is_verified, verified_by, verified_at, daily_report_id, created_at, updated_at}` (`models/todo.dart:88-103`). Note: decision 05 lists `done_report_id` / `verification_note`; the Flutter keys are `daily_report_id` with no `verification_note`. **Flutter wins**, and the unverify reason goes to the audit log only (`repositories/mock_schedule_repository.dart:242-248`). Update decision 05.
- **DailyReport** `{id, project_id, report_date, weather, status, submitted_by, reviewed_by, remarks, toolbox_meeting_held, created_at, updated_at}`. `weather` ∈ `sunny, cloudy, light_rain, heavy_rain, typhoon`; `status` ∈ `draft, submitted, approved, returned` (`models/daily_report.dart:3-40`). `submitted_by` = the author (set on create, not on submit).
- **ReportManpower** `{id, daily_report_id, trade, headcount, created_at, updated_at}`. `trade` is a trade **name** string, not an FK (`models/report_manpower.dart:16`).
- **ReportMaterialUsage** `{id, daily_report_id, material_id, quantity, created_at, updated_at}`. `material_id` → Phase 1.2 `MaterialItem`.
- **EquipmentLog** `{id, equipment_id, project_id, log_date, hours_used, daily_report_id, created_at, updated_at}`. `equipment_id` → Phase 1.2 `EquipmentItem`; `log_date` = the report date (`repositories/mock_daily_report_repository.dart:191-199`).
- **Issue** `{id, project_id, daily_report_id, type, reason, description, days_lost, created_at, updated_at}`. `type` ∈ `delay, safety, other`; `reason` ∈ `rain_typhoon, material, labor, client, other` (`models/issue.dart:3-35`).
- **ReportPhoto** `{id, daily_report_id, file_url, caption, latitude, longitude, taken_at, created_at, updated_at}`. `file_url` is a scoped API URL (see Uploads).
- **DailyReportDetail** `{report, manpower[], materials[], equipment[], issues[], photos[], todos[]}`. `todos` = to-dos with `daily_report_id == report.id` (`repositories/daily_report_repository.dart:10-29`, `mock_daily_report_repository.dart:67-83`).
- **Document** `{id, project_id, name, doc_type, file_url, uploaded_by, created_at, updated_at}`. `doc_type` ∈ `contract, plan, permit, as_built, other` (`models/document.dart:3-8`). Flutter derives the displayed file name from the **last path segment** of `file_url` (`models/document.dart:44`), so the download URL must end in the sanitized original file name.

## Projects (`ProjectRepository`)

| Method | Path | Who | Body → Response / refusals |
|---|---|---|---|
| GET | `projects/` | any role (scoped) | → `[Project]` scoped + redacted. Serves `getProjects()` and `getProjectsFor(userId, role)`: the server always scopes by caller and active role and ignores client-sent ids. Admin user-management (`features/user_management/viewmodels/user_form_viewmodel.dart:79`) gets all projects through `ALL_PROJECTS_ROLES`. |
| GET | `projects/{id}/` | any role (scoped) | → `Project`, or `404`. |
| POST | `projects/` | `owner` | `{code, name, location, latitude, longitude, client_id, contract_amount, down_payment_pct, retention_pct, start_date, target_end_date}` → `201 Project` with `status = requested` (client-sent `status` ignored, `mock_project_repository.dart:410-419`). In the same transaction the server creates the caller's `owner` assignment (`accepted`) so the project is in scope for the follow-up calls (Q6). Refusals `400`: "Enter the project code." / "Enter the project name." (`:384-389`); "Enter the contract amount." / "Contract amount must be greater than 0." (`services/project_rules.dart:15-16`); "Choose the start and target end dates." / "Target end date must be after the start date." (`:21-26`); "The down payment must be 0–100%." / "The retention must be 0–100%." (`:30-34`, labels from `mock_project_repository.dart:397-400`); "Another project already uses this code." (`:403-407`; the code is trimmed and upper-cased, `:402`, and the check is case-insensitive unique). Client checks (`features/projects/viewmodels/project_form_viewmodel.dart:77-83`): "Choose the client." / "This client has no app login yet. Ask the admin to create one." |
| PATCH | `projects/{id}/` | `owner` assigned (`features/projects/viewmodels/project_overview_viewmodel.dart:74`) | Same fields and validations. `status`, `actual_end_date`, `created_at` are read-only (`mock_project_repository.dart:421-429`). **Server-enforced** (today UI-only, `project_form_viewmodel.dart:89-98`): once the status is `ongoing/on_hold/completed/closed`, a changed `contract_amount` → `400` "Once work starts the contract amount changes only through approved variation orders." (*proposed text*). |
| POST | `projects/{id}/status/` | `owner` assigned | `{status}` → `Project`. Allowed moves (`services/project_rules.dart:39-51`): accepted→ongoing; ongoing→completed / on_hold; on_hold→ongoing; completed→closed. Request statuses have no manual moves. Refusals: "A project cannot move from {from.label} to {to.label}." (`:75-77`); "Only the owner can move a project to {to.label}." (`:78-80`). Moving to `completed` sets `actual_end_date` = today (`mock_project_repository.dart:447-449`). Server writes audit `project_status_changed {from,to}` and notifies every other **accepted** member: `project_status`, "{code} {name} is now {label}." (`:452-467`). |
| POST | `projects/{id}/resend/` | `owner` assigned | → `Project`. Only from `changes_requested`, else `400` "Only a project the client asked to change is sent again." (`:303-307`); not the assigned owner → `403` "Only the owner running this project can send it again." (`:308-312`). Effects: status → `requested`; client assignments in `changes_requested` → `pending`, `responded_at` cleared, request notification re-sent; audit `project_request_resent` (`:313-331`). |
| — | *(applyVariation)* | — | **No public route.** Contract amount and target end change only server-side when a VO is approved (Phase 4, called from `mock_billing_repository.dart:490`). |

### Assignments and requests

| Method | Path | Who | Body → Response / refusals |
|---|---|---|---|
| GET | `projects/{id}/assignments/` | staff roles (scoped); client → `403` | → `[ProjectAssignment]`, all responses incl. pending/declined (`repositories/project_repository.dart:26-27`). |
| GET | `project-assignments/?user={id}` | `admin`, or the caller for themself | → `[ProjectAssignment]` (`getAssignmentsForUser`). Filters `project`, `role_on_project`, `response`. `HttpProjectRepository.isAssigned` = this list filtered to `response=accepted` (or derive from `GET projects/` for the caller). |
| PUT | `users/{id}/assignments/` | `admin` | `{assignments: [{project_id, role}]}` → `[ProjectAssignment]`. Replaces the user's set; kept (project, role) pairs keep their row and response; new rows get the first response below and send their request (`mock_project_repository.dart:72-106`). Role not held → `400` "The user does not hold the {role.label} role." (`:76-83`). |
| POST | `projects/{id}/assignments/` | `owner` assigned (`project_overview_viewmodel.dart:75`) | `{user_id, role_on_project}` → `201 ProjectAssignment`. Role not held → `400` "The user does not hold the {role.label} role." (`:341-345`). A declined row for the same (project, user, role) is replaced (`:346-353`). Any other existing row → `400` "Already on this project." (`:354-361`). |
| DELETE | `project-assignments/{id}/` | `owner` assigned to that project, or `admin` | → `204` (`:375-377`). See R7. |
| GET | `project-requests/` | any role | → `[ProjectRequest]` = the caller's assignments in the active role with `response = pending` (`:158-166`). |
| POST | `project-assignments/{id}/respond/` | the assignee (else `404`) | `{response, note}` → `ProjectAssignment`. Not pending → `400` "You already answered this request." (`:181-183`). `response` `pending`/`not_sent` → `400` "Accept, decline or ask for changes." (`:197-200`). `changes_requested` by a non-client → `403` "Only the client can ask for changes." (`:190-195`). `declined`/`changes_requested` with a blank note → `400` "Add a note so the owner knows why." (`services/project_rules.dart:54-57`). The note is trimmed and stored, or null on accept (`:202`). Audit `project_request_{response}` `{role, note}` (`:212-218`). |

First response on assign (`mock_project_repository.dart:108-122`): `owner` → `accepted` at once. `client` → `pending`. `site_engineer` → `not_sent` while the project is `requested`/`changes_requested`, otherwise `pending`. A row created as `pending` sends a `project_request` notification (`:124-139`).

## Schedule (`ScheduleRepository`)

| Method | Path | Who | Body → Response / refusals |
|---|---|---|---|
| GET | `projects/{id}/categories/` | any role (scoped) | → `[Category]` by `sort_order` (`mock_schedule_repository.dart:33-36`); `budget` redacted per table. |
| GET | `projects/{id}/todos/` | any role (scoped) | → `[Todo]` for the project's categories (`:38-45`). The client needs these for progress (`features/client_portal/viewmodels/client_progress_viewmodel.dart:54-55`). |
| POST | `projects/{id}/categories/` | `owner` assigned (`schedule_viewmodel.dart:60`) | `{name, budget, sort_order}` → `201 Category`. Refusals: "Enter a category name." (`services/schedule_rules.dart:14-15`); "Budget cannot be negative." (`:17-18`); "Total category budgets (₱{total}) would exceed the contract amount (₱{contract})." (`:22-33`, the other categories' total excludes this one, `mock_schedule_repository.dart:55-64`). |
| PATCH | `categories/{id}/` | `owner` assigned | Same fields and rules. `project_id` is immutable (the mock lets the body move it, `:80-86`; R5). |
| DELETE | `categories/{id}/` | `owner` assigned | → `204`; cascades its to-dos (`:96-97`). Any verified to-do → `400` "This category has verified to-dos and cannot be deleted." (`services/schedule_rules.dart:72-75`). |
| POST | `todos/` | `owner` assigned to the category's project | `{category_id, title, start_date, end_date}` → `201 Todo` with done/verified flags false (`mock_schedule_repository.dart:117-128`). Refusals: "Enter a to-do title." (`schedule_rules.dart:49-50`); "Choose start and end dates." / "End date must be on or after the start date." / "Dates must fall within the project schedule ({start} to {target_end})." (`:54-69`). |
| PATCH | `todos/{id}/` | `owner` assigned | Only `title, start_date, end_date, category_id` (`mock_schedule_repository.dart:130-139`). Done/verify fields are read-only here. A new `category_id` must belong to the **same project** (`404` otherwise; R5). |
| DELETE | `todos/{id}/` | `owner` assigned | → `204`. Verified → `400` "A verified to-do cannot be deleted. Un-verify it first." (`schedule_rules.dart:77-79`). |
| POST | `todos/{id}/done/` | `site_engineer` or `owner` assigned (`schedule_viewmodel.dart:62-63`) | `{done}` → `Todo`. Un-done while verified → `400` "This to-do is verified. The owner must un-verify it first." (`schedule_rules.dart:81-83`). A no-op when unchanged (`mock_schedule_repository.dart:160`). Sets/clears `done_by`, `done_at`. Audit `todo_marked_done`/`todo_marked_not_done`. On done, notifies the project's owners: `todo_done`, "\"{title}\" was marked done on {code}. Verify it." (`:162-189`). |
| POST | `todos/{id}/verify/` | `owner` assigned (`schedule_viewmodel.dart:61`) | → `Todo`. "This to-do is already verified." / "Only to-dos marked done can be verified." (`schedule_rules.dart:85-89`). Sets `is_verified`, `verified_by`, `verified_at`; audit `todo_verified` (`mock_schedule_repository.dart:205-224`). |
| POST | `todos/{id}/unverify/` | `owner` assigned | `{reason}` → `Todo`. "This to-do is not verified." / "Enter a reason for un-verifying." (`schedule_rules.dart:91-97`). Clears the verify fields; audit `todo_unverified {reason}` (`mock_schedule_repository.dart:227-250`). |
| — | *(setReportLink)* | — | **No public route.** Linking happens only inside the daily-report save (below). `HttpScheduleRepository.setReportLink` throws `UnsupportedError`; its only caller is the mock report repo (`mock_daily_report_repository.dart:238,240`). |

Progress stays client-computed by `computeProjectProgress` (decision 05): only verified to-dos count, budget weights apply when **every** category has a positive budget, otherwise equal weights (`services/progress_calculator.dart:117-152`), and `as_of` counts only to-dos verified on or before that date (`:192-197`). Redaction interacts with this; see Q3.

## Daily reports (`DailyReportRepository`)

| Method | Path | Who | Body → Response / refusals |
|---|---|---|---|
| GET | `daily-reports/?project=1,2&status=&from=&to=` | staff roles (scoped); client → `403` | → `[DailyReport]` newest first (`mock_daily_report_repository.dart:50-64`). `project` ids outside scope are dropped silently, never trusted. |
| GET | `daily-reports/{id}/` | staff roles (scoped) | → `DailyReportDetail`, or `404`. |
| POST | `daily-reports/` | `site_engineer` assigned to `project_id` | Draft body (below) → `201 DailyReport` (`status = draft`, `submitted_by = caller`). |
| PUT | `daily-reports/{id}/` | the report's author (R6) | Same body; replaces every child list; `project_id` immutable. |
| POST | `daily-reports/{id}/submit/` | the author | → `DailyReport`. |
| POST | `daily-reports/{id}/approve/` | `owner` assigned | → `DailyReport`. |
| POST | `daily-reports/{id}/return/` | `owner` assigned | `{remarks}` → `DailyReport`. |
| GET | `projects/{id}/approved-material-usage/` | staff roles (scoped) | → `[ReportMaterialUsage]` from approved reports only (`:359-371`). |
| GET | `projects/{id}/approved-equipment-logs/` | staff roles (scoped) | → `[EquipmentLog]` from approved reports only (`:373-377`). |
| GET | `report-photos/approved/?project=1,2` | any role (scoped; client included) | → `[{photo, report}]` newest by `taken_at`, falling back to the report date (`:379-398`); used by `features/client_portal/viewmodels/client_photos_viewmodel.dart:44`. |

**Draft body** (from `DailyReportDraft`, `repositories/daily_report_repository.dart:65-91`): `{project_id, report_date, weather, toolbox_meeting_held, manpower: [{trade, headcount}], materials: [{material_id, quantity}], equipment: [{equipment_id, hours_used}], issues: [{type, reason, description, days_lost}], photos: [{id, caption}], todo_ids: [int]}`. `photos` lists **existing** photo ids to keep (and their captions); omitted photo ids are deleted. New photo files go through the upload route below.

**Draft refusals** (in mock order): project not `ongoing` → `400` "Daily reports can be added only while the project is Ongoing (it is {status.label})." (`services/project_rules.dart:86-90`, `mock_daily_report_repository.dart:94`); caller not the assigned site engineer → `403` "Only the site engineer assigned to this project can file its reports." (`:95-103`); "Choose the report date." / "A daily report cannot be dated in the future." (`services/daily_report_rules.dart:9-15`, using the server's local date); duplicate (project, date) → `400` "There is already a report for this project on this date." (`:108-117`; also a DB unique constraint); "Headcount must be greater than 0." (`daily_report_rules.dart:17-19`); "Choose a trade for each manpower row." (`mock_daily_report_repository.dart:120-124`); "Quantity must be greater than 0." (`daily_report_rules.dart:21-22`); "Hours must be greater than 0." / "Hours cannot exceed 24 in a day." (`:24-28`); "Describe each issue." (`mock_daily_report_repository.dart:133-135`); "Days lost cannot be negative." (`daily_report_rules.dart:30-31`); updating a non-editable report → "This report is {status} and can no longer be edited." (`:34-37`); a chosen to-do already done and linked elsewhere → "\"{title}\" is already done." (`mock_daily_report_repository.dart:231-242`). Unknown `material_id` / `equipment_id`, or a `todo_ids` entry from another project → `400` (*new*, IDOR guard).

**To-do linking on save** (`:231-242`): chosen to-dos get `daily_report_id = report.id`. To-dos no longer chosen that are still not done are unlinked.

**Submit** (`:246-288`): "Only draft or returned reports can be submitted." (`daily_report_rules.dart:39-41`); not the author → `403` "Only the site engineer who wrote this report can submit it." (`:251-255`). Effects in one transaction: every linked not-done to-do → done (same side effects as `todos/{id}/done/`), status `submitted`, audit `daily_report_submitted`, notify the project's owners `report_submitted` "Daily report for {code} on {date} is waiting for your approval."

**Approve** (`:290-321`): "Only submitted reports can be approved or returned." (`daily_report_rules.dart:43-46`); not the assigned owner → `403` "Only the owner of this project can review its reports." (`mock_daily_report_repository.dart:400-406`). Effects: linked done, unverified to-dos → verified by the approver (audit `todo_verified` each), status `approved`, `reviewed_by` set, `remarks` cleared, audit `daily_report_approved`, notify the author `report_approved` "Your daily report for {date} was approved." Approved usage and equipment hours now feed site inventory and costing (decision 05).

**Return** (`:323-357`): same review guards plus "Add remarks so the site engineer knows what to fix." (`daily_report_rules.dart:49-52`). Effects: status `returned`, `reviewed_by`, `remarks` trimmed, audit `daily_report_returned {remarks}`, notify the author `report_returned` "Your daily report for {date} was returned: {remarks}".

## Documents (`DocumentRepository`)

| Method | Path | Who | Body → Response / refusals |
|---|---|---|---|
| GET | `projects/{id}/documents/` | staff roles (scoped); client → `403` (Q5) | → `[Document]` newest first (`mock_document_repository.dart:74-79`). `contract` rows only for finance roles (`features/documents/viewmodels/project_documents_viewmodel.dart:46-55`). |
| POST | `projects/{id}/documents/` | `owner` or `site_engineer` assigned | `multipart/form-data` `{name, doc_type, file}` → `201 Document`. Others → `403` "Only the project's owner or site engineer can upload." (`mock_document_repository.dart:94-97`). "Enter the document name." (`:99-100`). Bad extension → `400` "Choose a file of type pdf, dwg, dxf, jpg, jpeg, png, doc, docx, xls, xlsx." (`:102-108`). Same (project, type, name) case-insensitive → `400` "A document with this name already exists in this section." (`:109-118`). `doc_type = contract` by a non-finance role → `403` "Only the owner or accountant can file contracts." (*proposed*; today UI-only, `project_documents_viewmodel.dart:47-50`). |
| DELETE | `documents/{id}/` | the uploader, or the assigned `owner` | → `204`; else `403` "Only the uploader or the owner can delete this document." (`mock_document_repository.dart:133-146`). Removes the stored file too. |
| GET | `documents/{id}/file/{file_name}` | same as list (scoped + type visibility) | Streams the file (see Uploads). |

## Uploads

- Multipart only, through Django's storage on a **private** `MEDIA_ROOT` that is **never** mounted under a public URL (no `static()`/`MEDIA_URL` serving, no public bucket). Files are stored under a random name (`uuid4` + extension); the original name is kept sanitized in the DB.
- **Documents:** extensions `pdf, dwg, dxf, jpg, jpeg, png, doc, docx, xls, xlsx` (`mock_document_repository.dart:13-24`). Content is sniffed by magic bytes against the extension (PDF `%PDF`, JPEG `FFD8FF`, PNG `89504E47`, OOXML zip `PK\x03\x04`, OLE `D0CF11E0` for doc/xls, DWG `AC10`, DXF text). Max **25 MB** (*proposed*).
- **Report photos:** `POST daily-reports/{id}/photos/` multipart `{file, caption, latitude, longitude, taken_at}` → `201 ReportPhoto`. Only the author, only while the report is `draft`/`returned` (same edit refusal text). `jpg, jpeg, png` only, magic-byte checked, max **10 MB** (*proposed*). `taken_at` defaults to now (`mock_daily_report_repository.dart:226`). Delete through the draft's `photos` list.
- **Serving:** `file_url` = absolute `…/api/v1/documents/{id}/file/{sanitized_name}` or `…/api/v1/report-photos/{id}/file/{sanitized_name}`. The endpoint re-checks JWT + active-role scope (+ contract visibility), and responds with `Content-Disposition: attachment` (inline for photos), `X-Content-Type-Options: nosniff`, the stored MIME type, and `Cache-Control: private, no-store`. Flutter must fetch these through the Dio client (with `Authorization` + `X-Active-Role`), not `Image.network`.
- Oversize requests are refused before the body is read (`DATA_UPLOAD_MAX_MEMORY_SIZE` / `FILE_UPLOAD_MAX_MEMORY_SIZE` plus a per-view size check) → `413` / `400` "The file is larger than {N} MB." (*proposed*).

## State machines

**Project status** (`services/project_rules.dart:39-51`, `mock_project_repository.dart`):

```
create ─▶ requested ──client accepts──▶ site_engineer_pending ──SE accepted & nobody pending──▶ accepted
            ▲   │                                   │ (SE declines: stays; owner assigns another SE)
            │   └─client changes_requested─▶ changes_requested ──owner resend──▶ requested
            │
 client declines (from requested) ─▶ project HARD-DELETED (+ all assignments)   (R1)
accepted ─▶ ongoing ⇄ on_hold ;  ongoing ─▶ completed (actual_end_date = today) ─▶ closed
```

- Client accept (`:242-260`): project → `site_engineer_pending`; every `not_sent` assignment → `pending` and its request is sent; notify owners "{who} accepted {code}. The site engineer has been sent the request."; then `_acceptIfReady`.
- `_acceptIfReady` (`:277-297`): from `site_engineer_pending` only. Becomes `accepted` when ≥1 site-engineer assignment is accepted and no client/SE assignment is still `pending`; notify owners "{code} is accepted by the client and the site engineer. Start it when work begins."
- Client changes requested (`:233-241`): project → `changes_requested`; notify owners "{who} asked for changes on {code}: {note}".
- Client declined (`:222-232`): notify owners "{who} declined {code} {name}, so it was deleted. Reason: {note}"; delete the project and its assignments.
- SE declined (`:265-270`): notify owners "{who} declined {code}: {note} Choose another site engineer." Project status unchanged. SE accepted: notify "{who} accepted {code}." then `_acceptIfReady`.

**Assignment response:** `not_sent → pending` (client accepts) `→ accepted | declined | changes_requested(client only)`; `changes_requested → pending` (owner resend); `declined` row is replaced on re-assign. `owner` rows start `accepted`.

**To-do:** `open → done` (SE/owner, or report submit) `→ verified` (owner, or report approve); `verified → done` (owner unverify + reason); `done → open` only while unverified.

**Daily report:** `draft → submitted → approved` (locked) ; `submitted → returned → submitted`. Editable only in `draft`/`returned` (`models/daily_report.dart:15-17`).

## Audit and notifications

Server-written in the same transaction, as in Phase 1. No client `POST`. Audit actions: `project_request_{accepted|declined|changes_requested}`, `project_request_resent`, `project_status_changed`, `todo_marked_done`, `todo_marked_not_done`, `todo_verified`, `todo_unverified`, `daily_report_submitted`, `daily_report_approved`, `daily_report_returned`. Add `project_created`, `project_updated`, `assignment_created`, `assignment_removed`, `user_assignments_set`, `document_uploaded`, `document_deleted` (*new*; the mock has none, but these are security-relevant). Notification types and texts are as quoted above (`project_request`, `project_status`, `todo_done`, `report_submitted`, `report_approved`, `report_returned`). Recipient sets must use **accepted** assignments only (R8). Notification `link` values are Flutter route strings (`AppRoutes.*`); the server stores the same strings.

## Security checks this phase must prove with tests

1. **IDOR across projects:** an owner, site engineer and client each assigned to project A get `404` on every project-B object route: `projects/{B}`, its assignments, categories, todos, documents and document file, daily-report detail, photo file, approved-photo/usage/equipment lists, plus every write (`PATCH`, `status`, `resend`, `todos/{id}/done|verify`, `daily-reports/{id}/approve`, `documents/{id}` delete). `?project=A,B` list filters return A rows only.
2. **Pending / declined / not_sent assignees** have no scope (`404` on the project), but see it in `project-requests/`.
3. **Client writes refused:** a client gets `403`/`404` on project create/patch/status, assignments, categories, todos (incl. `done`), daily reports, document upload/delete and photo upload. A client may only `respond` to their own pending request.
4. **Role/action matrix:** a site engineer cannot verify/unverify or approve/return; an owner not assigned to the project cannot; an admin cannot do schedule or report writes; an SE cannot edit or submit another SE's report; `X-Active-Role: site_engineer` on a user who also holds `owner` gets SE rights only.
5. **Redaction:** for `admin` and `site_engineer`, `contract_amount`, `down_payment_pct`, `retention_pct` and `Category.budget` are absent from list, detail, `project-requests/` and nested responses; for `client`, `budget` is absent; contract documents are hidden from the list and their file URL returns `404` for non-finance roles. Non-finance writes of these keys → `400`.
6. **Uploads:** wrong extension, extension/magic-byte mismatch (e.g. `.pdf` holding HTML/EXE), oversize, path-traversal file names (`../../x.pdf`) are refused; stored names are random; files are unreachable without a JWT and in-scope role; `MEDIA_URL` returns `404`.
7. **Server-only state:** `status`, `submitted_by`, `reviewed_by`, `is_done`/`is_verified`/`verified_by`, `uploaded_by`, `response` cannot be set through create/update bodies. The contract amount is locked once a project is ongoing. There is no public `applyVariation` route.
8. **Transitions:** every refusal text above has a test; client decline deletes atomically (or per R1 decision).

## Backend today vs. Phase 2 (`django-backend/apps/projects/`, read-only survey)

| Exists today | Phase 2 action |
|---|---|
| `Site` (`models.py:58-83`). Referenced by `site_inventory` (`SiteStock`, `Tool`, `Equipment`, `EquipmentLog`) and `requisitions.MaterialRequest` | **Keep for now** (Phase 3 owns those apps); Flutter has no Site, as the project carries `location/latitude/longitude`. Make `Project.site` nullable or drop it in Phase 2; decide Site's fate in Phase 3. |
| `Project` (`:86-142`): `site` FK, `manager` FK, status `PLANNING…CANCELLED` (upper case), `description`, `budget_amount`; no `location`, lat/long, `client_id`, `contract_amount`, `down_payment_pct`, `retention_pct` | **Replace fields**: add the Flutter keys, the lower-case status set, `code` upper-case unique; drop `manager` (→ owner assignment) and `budget_amount` (→ category budgets). Used by `financials` (`ProjectBudget`, `ExpenseLog`, `Collectible`) and `requisitions`; their status references (`requisitions/tests.py` imports `ProjectStatus`) must be updated in the same change. |
| `Contract` (`:145-191`) | **Remove** (folded into `Project.contract_amount/retention_pct/down_payment_pct`; the client is `client_id`). |
| `ProjectPhase`, `Milestone` (`:194-282`) | **Replace** with `Category` + `Todo` (decision 05). |
| Viewsets (`views.py`) all `IsAdminOrReadOnly`, **unscoped** querysets, no redaction; routes `sites/ projects/ contracts/ project-phases/ milestones/` | **Rewrite** to the routes above with scoping + redaction; delete `contracts/`, `project-phases/`, `milestones/`. |
| — | **Add**: `ProjectAssignment` (unique `(project, user, role_on_project)`), `Category`, `Todo`, `DailyReport` (unique `(project, report_date)`), `ReportManpower`, `ReportMaterialUsage`, `EquipmentLog`, `Issue`, `ReportPhoto`, `Document`; a `projects_for()` scoping helper; a redaction mixin keyed on `sees_finance()`; upload validators; private media storage. |
| `site_inventory.EquipmentLog` (`site_inventory/models.py:229-265`, a movement history with `event_type/site/note`) | **Name clash** with Flutter's `equipment_logs` (daily-report hours). Phase 2 adds the Flutter one under a distinct model/table, or replaces the old one; coordinate with Phase 3. |
| — | **Missing dependency:** `Client` (`clients` table, `models/client.dart`, incl. `user_id`). `Project.client_id` needs it, and it is in neither the Phase 1 nor the Phase 2 task list. Same for Phase 1.2 `MaterialItem` / `EquipmentItem`, which reports reference. |

## Flutter rules that look wrong or risky (flagged, not decided)

- **R1** A client decline **hard-deletes** the project and every assignment (`mock_project_repository.dart:222-232`), keeping the reason only in a notification, with no audit row about the project itself. Consider a `declined`/archived status plus audit instead.
- **R2** `saveProject` has **no role check** in the mock (`:383-430`), and `assign`/`unassign` have none either (`:336-377`). The UI alone gates them (`projects_viewmodel.dart:49`, `project_overview_viewmodel.dart:74-75`). The server must enforce them.
- **R3** The contract-amount lock is UI-only (`project_form_viewmodel.dart:89-98,163-165`). The mock accepts any change.
- **R4** The owner can both mark a to-do done and verify it (`schedule_viewmodel.dart:61-63`), so self-verification counts toward progress and earned value (billing).
- **R5** Category/to-do updates can move rows across projects (the body's `project_id` / `category_id` is trusted, `mock_schedule_repository.dart:80-86,131-139`).
- **R6** Any assigned SE can edit **another SE's** draft (only `isAssigned` is checked, `mock_daily_report_repository.dart:95-103,154-164`), while submit requires the author (`:251-255`). An update can also change `project_id` in the body while the stored report keeps its own (`:157-162` vs `:195`).
- **R7** Unassigning has no guard: it can remove the only accepted owner (the project then has no PM) or the only SE after `accepted`.
- **R8** `notifyProjectRole` notifies **every** assignment in the role, incl. declined/pending ones (`services/notification_service.dart:43-49`).
- **R9** Returning a report leaves its to-dos marked done (submit marked them, `mock_daily_report_repository.dart:256-265`; return doesn't revert), so they await verification after a rejection.
- **R10** Project creation is 1 + 3 + N separate calls (`project_form_viewmodel.dart:154-193`). Over HTTP a mid-way failure leaves a project with no client or no SE.
- **R11** `getReports`, `getDocuments`, `getAssignments`, `getProject` are unscoped in the mocks. The interface trusts `projectIds` from the caller. The server must ignore that trust.
- **R12** Photo and document "files" are placeholders: `PhotoDraft.fileUrl = 'mock://photos/…'` (`features/daily_reports/widgets/daily_reports_photo_dialog.dart:40-67`), and the document dialog sends only a typed `fileName` (`features/documents/widgets/documents_upload_dialog.dart:7-11`). There is no file picker or bytes, and `DocumentRepository.upload` has no file parameter.
- **R13** `ProjectAssignment.fromJson` defaults a missing `response` to `accepted` (`models/project_assignment.dart:79-81`), so a malformed response grants scope in the UI.

## Open questions

- **Q1 (blocking 2.3)** Redacting by omission breaks `Project.fromJson` for admin/SE (`models/project.dart:77-79`). Options: (a) send `0` instead of omitting; (b) make those three fields tolerate absence (`?? 0`) in the model. Recommend (b): a one-line model change per field, consistent with Phase 1 "omit".
- **Q2** Should the client see `contract_amount`, `down_payment_pct`, `retention_pct`? The client portal already shows the contract amount (VO detail page). Recommend yes, since these are their contract terms; only `budget` is internal.
- **Q3 (blocking correctness)** Omitting `Category.budget` changes progress weights for SE/client (equal vs budget-weighted). Options: (a) add a server-computed `weight` key (0–1) for all roles and use it in `progress_calculator.dart` when `budget` is absent; (b) a server `GET projects/{id}/progress/`; (c) don't redact budget (leaks pesos). Recommend (a).
- **Q4** Scope by assignment vs `projects.client_id`: should the server enforce that the client-role assignee == `clients.user_id` of `project.client_id`, and lock `client_id` after creation? Who builds the `Client` model and endpoints (Phase 1.2 or 2.1)?
- **Q5** Does the client get any document access (permits, as-built at handover)? Today: none (no portal page).
- **Q6** Server auto-creates the creator's owner assignment on `POST projects/`. Then `project_form_viewmodel.dart:181` (`assign(self, owner)`) would hit "Already on this project.". Drop that line in 2.3, or make an identical owner self-assign idempotent? Recommend dropping the line, and optionally accepting `client_user_id`, `site_engineer_id`, `categories[]` in `POST projects/` so creation is atomic (R10).
- **Q7** Upload size caps (25 MB documents / 10 MB photos) and whether DWG/DXF magic-byte sniffing is required or extension-only. Do photos need HEIC?
- **Q8** R12 needs a minimal Flutter UI addition (file picker for documents and photos) and a `DocumentRepository.upload` signature change (path/bytes). Approve as a recorded UI addition per MAP?
- **Q9** Should `admin` (non-finance) see contract documents and project finance keys at all? The Admin/Owner account holds `owner` too and switches role; pure admins would not.
- **Q10** App placement: keep everything in `apps/projects/`, or put the daily-report family in a new app? The `EquipmentLog` name clash with `site_inventory` needs a decision either way.
- **Q11** Is the report-date "future" check done in server local time (`Asia/Manila`) or the client's? Recommend the server's `timezone.localdate()`.
