# Phase 3 draft — procurement, site receipts and POS bridge

**Status: preparation only; NOT implementation approval.** Current source inspected read-only. Only this document is written; no production-code, database, POS, migration, test, branch or runtime changes. Routes below are **proposed CPMS routes**, not claims that they exist. Accounting blockers prevent claiming a complete financial integration.

## Authority and boundaries

- CPMS: `AGENTS.md`, `planning/backend-integration/MAP.md`, decisions `03-roles-and-access.md`, `04-pos-sync-and-connectivity.md`, `05-wbs-costing-and-pos-bridge.md`, and `contracts/phase-2-projects-and-site.md` (all decision/contract paths relative to `planning/backend-integration/`). Preserve Phase 2 accepted-assignment scope, active-role checks and history-preserving approach.
- Frontend truth: `flutter/lib/data/repositories/{procurement_repository,mock_procurement_repository,mock_procurement_data}.dart`; models listed below; `flutter/lib/data/services/{procurement_rules,inventory_calculator}.dart`. Repository draft/record classes have no existing JSON serializer: their snake_case wire mappings below are **proposals**, not existing serialization.
- POS truth, relative to `../qb_pos_inventory_system/`: `AGENTS.md`, `backend_django/apps/integration/{urls,views,serializers}.py`, `backend_django/apps/requisitions/services.py` (`import_request`, `expected_amount`, `request_read_back`, `close_requisition`, `project_payables`), `backend_django/apps/users/{permissions,authentication}.py`.
- **Client is READONLY.** Old mock/client approval paths and earlier planning wording grant no write authority. No procurement access for clients; only separately authorized portal reads. This draft does not silently amend other Phase 2 contracts.
- CPMS owns requests, PM purchasing decisions, physical site receipts/counts and local evidence. POS owns store review, releases and its project ledger. No shared DB/FKs, no inbound callbacks, no invented POS payment or release endpoint.

## Wire shapes

All proposed CPMS routes begin `/api/v1/`; snake_case; integer IDs, nullable IDs where shown by models; dates `yyyy-MM-dd`, timestamps ISO-8601 UTC. Decimal responses use finite decimal strings (accepted by `JsonUtils.toDouble`), never binary-float calculations on backend. Below, `T` expands to `created_at, updated_at` (nullable timestamps). These are exact model keys, not permission to mass-assign server fields.

| Model source (`flutter/lib/data/models/`) | Full finance-authorized response keys |
|---|---|
| `material_request.dart` | `{id, project_id, category_id, requested_by, needed_by, status, approved_by, T}` |
| `material_request_item.dart` | `{id, material_request_id, description, unit, quantity, purchase_order_id, T}` |
| `site_count.dart` | `{id, material_request_id, material_id, name, unit, expected, counted}` |
| `purchase_order.dart` | `{id, po_no, project_id, material_request_id, category_id, supplier_id, store_name, source, status, total_amount, delivery_address, or_number, receipt_photo_url, approved_by, T}` |
| `purchase_order_item.dart` | `{id, purchase_order_id, material_id, description, unit, quantity, unit_price, T}` |
| `delivery.dart` | `{id, purchase_order_id, received_by, received_at, receipt_photo_url, T}` |
| `delivery_item.dart` | `{id, delivery_id, purchase_order_item_id, qty_received, qty_damaged, T}` |
| `supplier_payment.dart` | `{id, purchase_order_id, amount, paid_on, method, reference_no, T}` |

Request status: `pending | rejected | ordered`. PO status: `released | purchased | partially_delivered | delivered | cancelled`. Source (`material_source.dart`): **`own_store | external`**, not `other_store`. Payment method (`payment_method.dart`): `cash | check | bank_transfer | e_wallet`.

Derived values are not extra persisted model keys: MR number `MR-{id padded 4}`; PO-item amount = quantity × unit_price; qty_good = qty_received − qty_damaged; external paid-on-purchase = `or_number != null` in current frontend.

Proposed wrappers mapped one-for-one to repository classes:

- `MaterialRequestDetail = {request: MaterialRequest, items: [MaterialRequestItem], counts: [SiteCount]}`.
- `DeliveryDetail = {delivery: Delivery, items: [DeliveryItem]}`.
- `PurchaseOrderDetail = {order: PurchaseOrder, items: [PurchaseOrderItem], deliveries: [DeliveryDetail], payments: [SupplierPayment], request_id: int|null}`.
- `BudgetCheck = {budget: decimal|null, committed: decimal, request_cost: decimal}`; remaining/exceedsBudget calculated by frontend.
- `InventoryLine = {material_id: int|null, name, unit, received, damaged, used}`; onHand/needsCount/key calculated by frontend.
- `Payable = {order: PurchaseOrder, delivered_value: decimal, paid: decimal}`; balance calculated as delivered_value − paid. **Cannot represent POS project-wide accounting faithfully; see blockers.**

## Proposed CPMS routes — every ProcurementRepository method

Lists return the above rows/wrappers, newest first where mock specifies; HTTP adapter must consume all DRF pages before returning a Dart list. `?project=1,2&status=...` maps `projectIds/statuses`; intersect scope server-side. Every nested FK must resolve within the same scoped project. Actor/user/role, status, totals, identity and timestamps come from server, never body `userId`/`role`.

| Dart method | HTTP + path | Body → result; active role |
|---|---|---|
| `getRequests` | GET `material-requests/?project=&status=` | → `[MaterialRequest]`; scoped staff |
| `getRequest` | GET `material-requests/{id}/` | → `MaterialRequestDetail`; scoped staff; adapter maps 404 to null |
| `checkBudget` | GET `categories/{id}/procurement-budget/?amount=` | → `BudgetCheck`; assigned owner/accountant; advisory, zero writes |
| `createRequest` | POST `material-requests/` | `{project_id, needed_by, items:[{description, unit, quantity}], counts:[{material_id, name, unit, expected, counted}]}` → `201 MaterialRequest`; assigned site_engineer |
| `rejectRequest` | POST `material-requests/{id}/reject/` | `{reason}` → `MaterialRequest`; assigned owner |
| `placeOrder` | POST `purchase-orders/` | `{request_id, category_id, source, lines:[{material_id, description, unit, quantity, unit_price}], covers_item_ids:[], delivery_address, store_name, or_number, receipt_photo_url}` → `201 PurchaseOrder`; assigned owner; irrelevant source-specific fields null/absent |
| `getPurchaseOrders` | GET `purchase-orders/?project=&status=` | → `[PurchaseOrder]`; scoped staff |
| `getPurchaseOrder` | GET `purchase-orders/{id}/` | → `PurchaseOrderDetail`; scoped staff; adapter maps 404 to null |
| `cancelPurchaseOrder` | POST `purchase-orders/{id}/cancel/` | empty → `PurchaseOrder`; assigned owner; remote outcome must be reconciled before final cancellation |
| `confirmDelivery` | POST `purchase-orders/{id}/deliveries/` | `{lines:[{po_item_id, received, damaged}], receipt_photo_url}` → `201 Delivery`; assigned site_engineer |
| `getDeliveries` | GET `deliveries/?project=` | → `[{delivery: DeliveryDetail, order: PurchaseOrder}]`; scoped staff |
| `getSiteInventory` | GET `projects/{id}/site-inventory/` | → `[InventoryLine]`; scoped staff; derived, zero writes |
| `getPayables` | GET `procurement-payables/?project=` | → `[Payable]`; finance only; financial semantics blocked below |
| `recordPayment` | POST `purchase-orders/{id}/payments/` | `{amount, paid_on, method, reference_no}` → `201 SupplierPayment`; accountant only; **disabled for POS-owned payable posting pending accounting decision** |
| `deliveredValueByCategory` | GET `projects/{id}/delivered-value-by-category/` | → `{"category_id_as_string": decimal}`; finance only; adapter converts keys to int; valuation blocked for unverified prices |

Bridge additions (not in current interface): proposed GET `purchase-orders/{id}/pos-status/` returns separate `{pos_request_id, pos_sync_status, pos_status, pos_expected_amount, last_checked_at, stale, detail}`; proposed POST `purchase-orders/{id}/pos-sync/` enqueues retry for assigned owner. No raw UUID token, credentials or unredacted upstream payload in these responses. Their Flutter DTO/UI is future work: current `PurchaseOrder` has **no** POS fields despite MAP's forward-compatibility claim. GET returns cached snapshot only; deliberate refresh/polling runs through background work or a future explicit action, not write-on-read hooks.

## Rules and safe refusals

- MR create: ongoing project, assigned site engineer, needed-by ≥ server local date, ≥1 described positive-quantity line. Every inventory row with nonzero on-hand (including negative) requires a count. Store **server-calculated expected** snapshot; reject stale submitted expected with a retryable conflict rather than trusting it. Count variance is evidence, **not** stock adjustment.
- Owner answers MR by placing orders, no separate CPMS approve step. Reject pending only, nonblank reason. Several POs may answer one MR; `ordered` means at least one order, not every requested item supplied. Covered item IDs unique, belong to MR and not already covered; lock coverage against concurrent orders. Category must belong to MR's project. Budget warning is advisory per `BudgetCheck`, not a new hard spending ceiling.
- Own-store requires delivery address, material IDs with explicit selling-unit `pos_code` mappings and one unambiguous own-store supplier. External requires store name, OR number and validated private receipt evidence; stays CPMS-only. Do not silently infer catalog identity or unit compatibility by typed-name match as mock does. Snapshot line quantities/units/prices and category on order.
- `released` in existing CPMS PO enum means **PM order sent to own store**, NOT physical release, acceptance or delivery. Local save/queue and successful import are not release evidence. Keep POS status separate. POS released quantities likewise never automatically create site receipts.
- Receipt: at least one received > 0; unique PO-line IDs; received/damaged ≥ 0, damaged ≤ received; cumulative received (including damaged) ≤ ordered. Lock PO/lines and validate cumulative totals atomically. Complete by received quantity as mock; damaged goods do not enter usable inventory or delivered-good costing. Own-store receipt requires reconciled released-quantity evidence; never grant receipt authority merely from `synced`. Closed/declined shortfalls require explicit reconciliation, not manufactured delivery or completion.
- Site inventory = received − damaged − approved daily-report usage. Key = `m{id}` or `n:{trimmed lowercase name}`; preserve negative on-hand, never clamp or overwrite from count. Name/unit collisions need resolution before merging unlike units. Material actuals per decision 05 = good delivered quantity × **substantiated** PO unit price grouped by category, not ordered total or POS expected_amount.
- Cancellation: refuse any PO with site receipts and any paid external purchase; enforce owner scope (missing in mock cancellation). A POS release can exist without site delivery: close only abandons remainder and never reverses a release/debt. Do not mark full PO cancelled or reopen all coverage when any released quantity exists. Resolve timeout/unknown close outcome before final state or replacement order.
- All decimal inputs (including query amount and upstream responses) must be finite, bounded and precision-validated before arithmetic/writes. Reject NaN, ±Infinity, booleans, malformed/overflowing values and excess precision; never silently round quantities. Own-store POS quantity is Decimal(12,2), ≥0.01, ≤9999999999.99; whole-unit constraints can still be refused by POS because catalog omits `is_whole`. Proposed CPMS money/quantity bounds must be locked before implementation; use decimal arithmetic and explicit rounding policy, no mock float `+0.005` tolerance. Negative price/count/payment rules remain enforced; price ≥0, count ≥0, payment >0 and ≤ supported unpaid balance.
- Any validation, authorization or duplicate/conflict refusal leaves **zero business writes/outbox/file side effects**, including no partial MR/order/receipt/payment. Successful related rows, audit and outbox commit together; authentication/security audit can independently record refusal. Duplicate HTTP submissions need durable operation identity, not just POS idempotency.
- Preserve mock business error texts, e.g. “Add at least one item.”, “This request was rejected.”, “Unknown PO line.” and “Damaged cannot exceed received.”; Phase 2 conventions: business validation 400 `{detail}`, forbidden action 403, cross-project object 404. New conflict/stale/blocked-accounting refusals need documented distinct codes; never disguise unsupported accounting as success.

## Actual POS surface (not proposed)

Base `/api/v1/integration/cpms/`, JWT `CPMS Service` account. Service has no till/admin/payment API authority. All calls originate on CPMS backend; desktop never holds service credentials. HTTPS with certificate verification outside explicitly trusted local transport; configured allowlisted origin, no caller-supplied URLs. Optional upcoming gateway header is backend-only deployment configuration, **not yet a verified POS requirement**, not a replacement for JWT; header name/value and secrets omitted here.

| Method + relative route | Actual shape/meaning |
|---|---|
| GET `customers/` | DRF `{count,next,previous,results:[{id,name}]}`; active CONTRACTOR/CONSTRUCTION_FIRM payers |
| GET `materials/` | same pagination, rows `{code,product,unit}`; selling-unit barcode; **no price, stock, cost, ID or whole-unit flag** |
| POST `requests/` | `{cpms_request_id, token: UUID, project:{cpms_project_id,name,payer:POS_customer_id}, requester_name, approver_name, notes?:string, items:[{code,quantity:decimal_string}]}` → 201 new / 200 existing `{id,req_number,cpms_request_id,status,items:[{code,quantity}]}` |
| GET `requests/{cpms_request_id}/` | `{cpms_request_id,req_number,status,decline_reason,expected_amount:decimal_string|null,items:[{code,requested,released,outstanding,available:boolean|null,decline_reason}]}`; quantities are strings |
| POST `requests/{cpms_request_id}/close/` | empty → same read-back; closes WAITING/ACCEPTED/PARTIAL; DECLINED/RELEASED/CLOSED are unchanged 200; CANCELLED → 409 REQUEST_CANCELLED; missing → 404 REQUEST_NOT_FOUND |
| GET `projects/{cpms_project_id}/payables/` | `{cpms_project_id,total,paid,balance}` money strings; existing project with no ledger rows → zeros; unknown project → 404 PROJECT_NOT_FOUND |

Import creates **WAITING**: CPMS PM approval is distinct from POS store review. Store acceptance/partial release follows POS workflow. Read-back can include legacy states; retain raw value, never force unknown upstream state into CPMS enum. Outstanding remains requested − released even CLOSED or declined. Current service implementation, not stale close-view docstring, establishes WAITING/DECLINED close behavior above.

`expected_amount` is a live **budget**, not invoice/debt: known released total + current selling prices × available outstanding, outstanding sum rounded once HALF_UP. Can change without new release; can retain abandoned shortfall after close. Null means unknown (WAITING/DECLINED, legacy unknown released amount, or close before review), never free goods. Read-back supplies **no per-release monetary feed, invoice lines, sale IDs, line prices or payment rows**.

POS project `total` sums ledger original_amount; `balance` sums balance_due; `paid = total − balance` includes **return credits and other balance reductions**, not solely cash payments. Never allocate these project totals to a PO/category or create SupplierPayment rows from their delta.

## Durable identity, retry and history

Future order transaction saves an immutable `pos_request_id` — a UUID minted once, **not** `po_no` (3.1a build, decision 04) — plus `pos_token` (UUID, minted once, never regenerated), the stable `cpms_project_id` mapping (decision 04 uses project code), the complete normalized import payload and a durable outbox row before any network I/O. **The identity 3.1b must send on the wire is `cpms_request_id = po.po_no`** (e.g. `PO-2026-0001`, the human, unique order number); `pos_request_id` is CPMS's own durable operation id and is never sent as `cpms_request_id`. Read-back and close therefore address `requests/{po_no}/` and `requests/{po_no}/close/`. Both values are unique and stable, so neither may be regenerated on retry. Snapshot **all** payload fields, including payer/project names, requester/approver, notes, codes and quantities; don't rebuild retry from mutable masters. POS accepts same request ID with changed valid payload but returns first stored copy unchanged: identity alone does not prove new payload applied. New project imports may update POS project name/payer; reassignment/rebilling needs controlled history, not accidental retry mutation.

Use `pending_sync | synced | failed` independently from POS status, plus durable attempt/outcome/next-attempt metadata. Timeout, disconnect, invalid success body or lost worker acknowledgment = **unknown outcome**, not safe failure. Reconcile GET by fixed ID and retry exact stored payload/token; a GET 404 after unknown outcome permits only same-identity retry, not new PO/token. Persist attempts/backoff; serialize claims per operation; retry bounded transient failures, refresh backend auth safely; permanent validation/token conflicts require review. Never regenerate token on 409 TOKEN_TAKEN. Validate 200/201 body identity/lines before reporting synced; mismatches block reconciliation.

Close operations also need durable intent/retry and no full-cancel conclusion until reconciled; coordinate pending import/close jobs so cancellation cannot later import a fresh live request. Poll/read snapshots and staleness are explicit; no inbound POS callbacks are implemented. Redact credentials and bearer UUID from logs/audit; current legacy `PosSyncLog.request_payload` must not retain them unchecked.

Preserve existing `django-backend/apps/requisitions/{models,views,services,urls}.py` records (`MaterialRequest`, items, `ReleaseToken`, `PosSyncLog`), `apps/site_inventory/models.py` site/stock/tool/equipment history and financial references. Additive migration/mapping only after inventory of links; retain unmappable raw statuses/values, no guessing legacy PO, supplier, release or price. Existing `/requisitions/`, `/release-tokens/` and legacy redeem callback are **not** this contract; quarantine/retire unsafe public paths explicitly during implementation without deleting history. Legacy `PosAPIClient` calls ordinary requisitions/token/collectibles routes and has no durable queue: it is not the actual bridge contract.

## Access, evidence and open decisions

Use Phase 2 `projects_for` and capability helpers with `X-Active-Role`; pending/not_sent/declined assignments confer no access. Owner: accepted assigned projects, finance and purchasing. Site engineer: accepted assigned projects, operational reads/request/count/receipt only. Accountant: all scoped projects, finance reads/payment role. Pure admin: all operational projects, **not finance**, no owner procurement writes. Client: no internal procurement routes, no writes. Server checks every child ID/upload/download/retry; no project IDs trusted from caller. Reject finance keys from non-finance writers; omit `unit_price`, `total_amount`, budget/valuation/payable/payment data and monetary POS metadata from non-finance responses. Receipt photos/OR evidence are finance-sensitive unless explicitly approved for operational access; scoped private storage, validated MIME/size, no arbitrary URL fetching or public media. Server audit actor, prior/new state and operation identity; notifications only to accepted scoped members, never leaked amounts/tokens.

### BLOCKERS — owner/accounting facts required before financial implementation

1. **Own-store valuation:** actual per-line/per-release invoice values are unavailable on this POS boundary. CPMS master/draft price can be an estimate, not silently authoritative actual cost. Decide approved independent evidence/manual reconciliation versus additive POS monetary endpoint. **Never infer line prices from aggregated expected_amount**, including fully released or single-line cases. Decision 05's future catalog-price claim is not current capability.
2. **Debt/payment ownership:** current `[Payable]` is per-PO delivered-good valuation minus local payments; POS debt is project ledger across releases, returns/credits and settlement. Decide authoritative ledger, credit/damage/tax/discount treatment and reconciliation. No fake POS payment posting: service cannot post payments or receipt photos. Keep POS project summary separate from local PO payables; no double counting or fabricated allocation. Block own-store `recordPayment` as settlement until explicit ownership/evidence contract exists.
3. **Exact redacted frontend parsing:** current PO `total_amount` and item `unit_price` parsing requires a value. Server must not leak prices to SE/admin; absent-key-safe HTTP/model adaptation is required, not sending fictional zeros as accounting truth. Existing SupplierPayment lacks planned `external_ref`/`receipt_photo_url`; proposed bridge fields/wrappers likewise require explicit additive DTO work.

### Open trade-offs (not permission to guess)

- Keep legacy PO `released` with unmistakable “ordered / awaiting store review” UI plus separate sync/store/receipt states, versus approved enum migration. Preserve history either way.
- Confirm precision/rounding for CPMS prices and derived values; explicit unit mapping/whole-unit refusal UX; unique POS codes/own-store supplier; project-code rename stability after first sync.
- Decide partial-release cancellation/coverage reopening and damaged replacement/return workflow; don't subtract POS debt automatically. Define evidence and freshness needed for a site receipt when POS is offline.
- Confirm local payment scope (external purchases already paid are excluded by mock), payment evidence uploads, duplicate-submission keys and private photo visibility. Draft route reservations do not enable these operations.

**Preparation acceptance:** only this file changed by this task; no suites/DB/API calls run. Later implementation must prove role/project isolation, nonfinite and zero-write refusals, concurrent receipts/coverage, immutable retry and unknown outcomes, partial close preservation, stale/null POS amounts, credit-inclusive paid semantics and legacy-history preservation before activation.

---

## 3.1a Built as — operational procurement (backend lane, review round 1 fixed)

**Status: built; focused tests green; review round 1 returned CHANGES_REQUIRED and those fixes are in — awaiting re-review, NOT ticked.** Scope is the operational half of this contract only. **Not built here:** the POS HTTP client and its retry worker (task 3.1b), payables / supplier payments / `delivered-value-by-category` (financial blockers below), and all Flutter work (task 3.2). `released` still means "order sent to the own store" — nothing in this build claims a physical release, a POS status, or a debt.

### Data model — additive, history kept (`requisitions/migrations/0003` + `0004_legacy_procurement_data`)

Same rule as Phase 2's `0004/0005`: the existing tables are extended in place, no table, row or column is dropped, and every unmappable legacy value is retained verbatim.

- `MaterialRequest`: `status` moved to the Flutter enum (`pending | rejected | ordered`), plus `category`, `needed_by`, `approved_by` and `legacy_status`. The pre-Phase-3 status code is copied into `legacy_status`; `needed_date → needed_by` (the same fact); `reviewed_by → approved_by` **only** for rows that map to `ordered`, because `approved_by` means "the owner who answered with an order". Mapping: `DRAFT/PENDING/APPROVED/PARTIALLY_APPROVED → pending`, `REJECTED/CANCELLED → rejected`, `RELEASED → ordered`. `request_no` is kept and now nullable for new rows (the wire number is derived: `MR-{id:04d}`).
- `MaterialRequestItem`: `quantity_requested` is the wire `quantity`; `item_sku` became optional; `purchase_order` added for coverage. `quantity_approved`, `quantity_released` and `unit_cost` stay as legacy columns and are **never serialized** (they carry prices).
- New: `SiteCount`, `PurchaseOrder`, `PurchaseOrderItem`, `Delivery`, `DeliveryItem`, `PosOutboxJob`.
- `PurchaseOrder` POS fields exist from day one: `pos_request_id` (UUID, minted once), `pos_token` (UUID, **never serialized**), `pos_sync_status` (`not_applicable | pending_sync | synced | failed`), `pos_expected_amount` (null until read-back; never invoice evidence).
- `ReleaseToken` / `PosSyncLog` rows are untouched; their **routes are retired** (below).

### Routes shipped

| Route | Role | Result |
|---|---|---|
| `GET material-requests/?project=&status=` | staff, scoped | `[MaterialRequest]`, newest first, projects intersected server-side |
| `GET material-requests/{id}/` | staff, scoped | `MaterialRequestDetail {request, items, counts}` |
| `POST material-requests/` | assigned `site_engineer`, ongoing project | `201 MaterialRequest` |
| `POST material-requests/{id}/reject/` | assigned `owner` | `MaterialRequest` |
| `GET purchase-orders/?project=&status=` / `GET purchase-orders/{id}/` | staff, scoped | rows / `{order, items, deliveries, payments: [], request_id}` |
| `POST purchase-orders/` | assigned `owner` | `201 PurchaseOrder` |
| `POST purchase-orders/{id}/cancel/` | assigned `owner` | `PurchaseOrder` |
| `POST purchase-orders/{id}/deliveries/` | assigned `site_engineer` | `201 Delivery` |
| `GET deliveries/?project=` | staff, scoped | `[{delivery: DeliveryDetail, order}]` |
| `GET projects/{id}/site-inventory/` | staff, scoped | `[InventoryLine]`, derived, zero writes |
| `GET categories/{id}/procurement-budget/?amount=` | `owner` / `accountant`, scoped | `BudgetCheck {budget, committed, request_cost}`, advisory, zero writes |
| `GET purchase-orders/{id}/receipt/{name}` / `GET deliveries/{id}/receipt/{name}` | finance roles, scoped | private receipt evidence (`attachment`, `no-store`) |

**Retired on purpose:** `requisitions/`, `requisition-items/`, `release-tokens/` (including the `redeem/` callback — a bearer secret any authenticated caller could redeem) and `pos-sync-logs/`. They bypassed Phase 2 project scoping entirely; their models and rows stay, and the retired paths now answer `404` (tested).

### Security actually enforced

- **Scope first, role second, rule third**: out-of-scope objects are `404` (never "not yours"), in-scope-but-wrong-role is `403`, business refusals are `400 {detail}`.
- **Role matrix**: `client` gets `403` on every procurement route; `site_engineer` writes requests and receipts only; `owner` places/cancels orders and rejects requests; `accountant` reads and checks budgets; pure `admin` reads only and is **not** a finance role.
- **Finance redaction** (omitted, never zero-filled): `unit_price`, `total_amount`, `or_number` and `receipt_photo_url` for `admin` and `site_engineer` (OR evidence is finance-sensitive per the access section). Receipt files answer `404` for them.
- **No money in the audit trail**: `AuditLog.details` carries ids, counts and source only (`{request_id, lines, source, pos_request_id}`), because pure `admin` — not a finance role — can read `/audit-logs/`. Notification texts never carry an amount either.
- **Server-owned**: `status`, `totals`, `po_no`, `approved_by`, `requested_by`, `pos_*`, timestamps are read-only; a body trying to set them changes nothing (tested).
- **Uploads**: external receipt evidence and delivery photos go through the Phase 2 photo validator (extension + magic bytes + 10 MB) into the private media root with a random stored name; a refused upload writes nothing.
- **Zero-write refusals**: every refusal happens before the first write; the receipt file is deleted again if a later step fails, so no orphan files or half-orders.

### Receipt and order rules proven by test

Unique PO lines per delivery, at least one `received > 0` (checked before the per-line ids, matching the mock's order), `damaged ≤ received`, cumulative `received + already ≤ ordered`, and PO/lines re-read under `select_for_update()` — a threaded test races two receipts for the last 10 bags and exactly one wins. Damaged goods never enter inventory or delivered-good value. Cancellation refuses once any delivery exists or the purchase was paid at the store; it reopens coverage, returns a request with no live order to `pending`, drops a never-sent POS import, and records a close intent when a POS import already exists.

Coverage is locked, not just pre-checked: `place_order` validates item membership before any write, then re-reads the covered item rows under `select_for_update()` **inside** the transaction, after the request row lock, so two concurrent orders cannot both cover one item — a threaded test (`OrderCoverageConcurrencyTests`) races two orders for the same item, asserts exactly `[201, 400]`, one covering order and one outbox row.

### Decisions taken in 3.1a (each a **revisable default**)

1. **`pos_request_id` is a UUID** minted once at placing (task brief), **not** `po_no`; decision 04 and this contract's "Durable identity" paragraph were updated in place. **3.1b must send `cpms_request_id = po.po_no`** (the human, unique order number) with `token = pos_token`; `pos_request_id` stays CPMS's internal durable operation id and never goes on the wire. Read-back/close address `requests/{po_no}/`. Both values are unique and stable; neither is ever regenerated on retry.
2. **Receipt evidence is an uploaded file, not a URL.** The draft's `receipt_photo_url` body key is ignored; `receipt_photo` (multipart) is required for external orders. Serialized back as a scoped download URL. No arbitrary URL is ever fetched.
3. **Receipt evidence is finance-only** (owner/accountant). The site engineer who uploads a delivery photo cannot read it back; revisit if that hurts the site workflow.
4. **Counts for material the system does not track** are stored as submitted evidence (expected = submitted); counts for tracked material always use the server snapshot and a mismatch is `409 STALE_SITE_COUNT`.
5. **Own-store supplier must be exactly one**: zero → "Set up the own store in the supplier list first."; more than one → a new refusal text. Also new: `MISSING_POS_CODE`, `DUPLICATE_PO_LINE`, `BAD_LINES`, `CHOOSE_SOURCE`, `PRECISION`, `TOO_LARGE`, `STALE_SITE_COUNT`, `CLIENT_NO_PROCUREMENT`, `NOT_FINANCE_BUDGET`, `AMOUNT_REQUIRED`, `AMOUNT_INVALID`.
6. **Role vs status wording for reject**: a wrong role is a `403` with the mock's PM text; a wrong status keeps the mock's exact sentence, including the caller's role label (`… cannot be rejected by a owner / project manager.`).
7. **Cancellation of an already-synced own-store order** records a `close` outbox intent instead of refusing, because the POS may hold a release the site never received; nothing is reversed here.
8. **Legacy status mapping** (see above) treats `APPROVED` as `pending`: approval was never an order in the new model, and saying `ordered` would claim an order exists.
9. **Coverage and cancellation do not reopen a delivered PO's items**; only an undelivered cancelled order releases its covered request lines.
10. **`payments` stays `[]`** in the PO detail wrapper so the Flutter detail parser keeps working while payables are blocked.
11. **`or_number` is finance-only** (owner/accountant), like receipt evidence: the operational roles get the order row without the OR number. Revisable default — owner may grant operational read access.
12. **A supplied count `material_id` must be an existing price-list id** (`Pick the counted material from the price list or leave it blank.` → `400`); absent/null still stores name-only evidence. This closes a `500` (junk string → `DataError`, unknown id → `ForeignKeyViolation`).
13. **The owner notification link `/deliveries/confirm/{po_id}` is a real Flutter route** (`flutter/lib/routes/routes.dart` → `AppRoutes.deliveryConfirm`, rendered by `DeliveryConfirmPage`), so it was kept and annotated with the `AppRoutes` name like the Phase 2 link constants.

### Undeclared relaxations — explicit 3.1a interim defaults (3.1b **must** re-close)

Review round 1 found two behaviours that the rules above do not permit, but that must stand until a POS read-back exists. Both are **interim 3.1a defaults, not contract-compliant**:

1. **Own-store receipts are accepted while the PO is merely `released`** (order sent to the store), with no reconciled POS release evidence. The contract requires reconciled released-quantity evidence before granting receipt authority; the POS client/`pos-status` read-back that would supply it is 3.1b. Until then the physical site receipt is the only evidence CPMS has, and refusing every receipt would block the site entirely.
2. **Cancelling an own-store order reopens its covered request lines** regardless of POS release state (only a `close` outbox intent is recorded). The contract forbids reopening coverage when any released quantity exists; POS released quantities are unreadable in 3.1a.

3.1b **must re-close both** the moment `pos-status` read-back exists: own-store receipt authority gated on reconciled release evidence, and coverage reopening gated on `released == 0`. **Owner confirmation is outstanding** for the interim behaviour (and for the offline-receipt evidence question in the open trade-offs).

### Test evidence (`../temp/cpms/3.1a/`)

`red.log` — RED first: 50 new tests, 15 failing (missing texts, nullable-FK `FOR UPDATE`, coverage parsing, multipart encoding, thread visibility). `green-4.log` — 69/69 `apps.requisitions` tests OK (50 new contract tests, 13 legacy-model tests, 6 retired-route tests, 5 migration-preservation tests). `green-5-crossapp.log` — 78/78 OK when run together with the Phase 2 migration test (this migration depends on `apps_projects.0006`, which that test rolls back). `check-drift.log` — `check` clean, `makemigrations --check --dry-run` → "No changes detected".

Review round 1 fixes (same directory): `fix-red.log` — the five new tests fail first (coverage race answered `[201, 201]`, audit detail carried `total`, `or_number` leaked to admin, `'abc'` count id raised `ValueError` → `500`, empty receipt answered `Unknown PO line.`). `fix-tests.log` — 85/85 OK in default order (`apps.requisitions.tests_procurement` 56, `apps.requisitions.tests` 14, `apps.requisitions.tests_migration_procurement` 6, `apps.projects.tests_migration` 9). `fix-check-drift.log` — `check` clean, "No changes detected".

Not proven here: POS network behaviour, retry/unknown outcomes (3.1b), any financial route, Flutter clients.
