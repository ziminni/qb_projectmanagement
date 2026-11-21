# Own-store order matching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every store product orderable, store price locked and enforced, line-by-line matching, and the request showing in POS within seconds.

**Architecture:** CPMS backend links store products during `pos-catalog/` reads and prices own-store orders from the store; after commit it kicks the outbox in a thread. CPMS Flutter replaces the own-store form's three cards with one matching card. POS Flutter re-reads the requests page and badge on a 15 s timer.

**Tech Stack:** Django/DRF (CPMS), Flutter/Provider (CPMS + POS).

**Spec:** `docs/superpowers/specs/2026-11-20-own-store-order-matching-design.md`

## Global Constraints

- CPMS never writes the POS database. A price the store did not give is never stored or shown as ₱0.
- Store unreachable on order → refuse: "The store could not be reached, so its price could not be confirmed. Try again."
- Product with no store price → refuse: "The store has no price for <name>."
- POS page/badge refresh: 15 s. CPMS worker default pass: 10 s.

## Review Focus

- Two store products with the same name, or a store name equal to a CPMS material linked to another code → `"<product> (<code>)"`, no IntegrityError (Task 1 test).
- App sends a price lower than the store's → saved price and total are the store's (Task 2 test).
- Inline send fails (store down) → order saved, job stays PENDING (Task 2 test).
- Owner unmatches then re-matches a requested item → one line, one cover (Task 3 test).
- POS page disposed while a timer read is in flight → no notify after dispose (Task 4 test).

---

### Task 1: Link every store product on catalogue read (CPMS backend)

**Files:** Modify `django-backend/apps/requisitions/pos_live_views.py` (`pos_catalog_view`); Test `apps/requisitions/tests_pos_live.py` (`PosCatalogTests`).

**Produces:** `link_store_products(rows: list[dict]) -> dict[str, int]` (code → MaterialItem pk) in `pos_live_views.py`.

- [ ] Tests: `test_an_unlinked_store_product_gets_a_cpms_material` (row `NAIL-4` → `material_id` not null, MaterialItem name `Common Nail 4in`, unit `KG`, pos_code `NAIL-4`); `test_an_unlinked_cpms_material_with_the_same_name_is_linked` (existing `Common nail 4in` with no pos_code gets `pos_code='NAIL-4'`, count unchanged); `test_a_name_taken_by_another_code_gets_the_code_in_brackets`.
- [ ] Run `docker exec cpms_backend python manage.py test apps.requisitions.tests_pos_live --noinput` → new tests FAIL.
- [ ] Implement in `transaction.atomic()`; `default_unit_cost` = store price or 0; on `IntegrityError` re-read once.
- [ ] Re-run → PASS.

### Task 2: Store price enforced + instant send (CPMS backend)

**Files:** Modify `apps/requisitions/procurement_services.py` (own-store branch of order creation), `apps/requisitions/rules.py`, `apps/requisitions/management/commands/run_pos_outbox.py` (default 10), `apps/requisitions/pos_worker.py`; Test `apps/requisitions/tests_procurement.py`.

**Produces:** `store_prices(codes: set[str]) -> dict[str, Decimal]` in `procurement_services.py` (raises `RuleRefused` with the constraint copy on `PosError`); `send_soon()` in `pos_worker.py` (thread running `run_once(limit=5)`, closes its DB connection, swallows errors), called via `transaction.on_commit` when `settings.POS_SEND_ON_ORDER` (default True).

- [ ] `ProcurementFixtures.setUp` patches `apps.requisitions.procurement_services.store_prices` to return `{'CEM-40KG': Decimal('250.00')}`.
- [ ] Tests: `test_own_store_order_uses_the_store_price_not_the_apps` (send 1.00 → item 250.00, total qty×250); `test_own_store_order_is_refused_when_the_store_is_down`; `test_own_store_order_is_refused_when_the_store_has_no_price`; `test_placing_an_own_store_order_schedules_a_send` (captureOnCommitCallbacks, `send_soon` patched, called once).
- [ ] Run → FAIL. Implement. Run whole `apps.requisitions` → fix tests that asserted the app's price (260.00) on own-store orders to the store price.

### Task 3: Matching card + locked price (CPMS Flutter)

**Files:** Modify `features/procurement/viewmodels/order_form_viewmodel.dart`, `features/procurement/views/own_store_order_form.dart`, `features/procurement/widgets/procurement_line_editor.dart` (`lockPrice` flag); Create `features/procurement/widgets/store_product_picker.dart`, `features/procurement/widgets/own_store_match_card.dart`; Test `test/.../order_form_viewmodel_test.dart` (existing location).

**Produces (viewmodel):** `Map<int, LineDraft> matches`; `LineDraft? matchFor(int itemId)`; `void match(MaterialRequestItem item, StoreProduct p)` (sets line qty = item.quantity, unit/price from p, adds to `lines` and `covers`, replaces earlier match); `void unmatch(int itemId)`; `List<StoreProduct> rankFor(String text)` (word-overlap score, then name); `String? catalogError`; `Future<void> reloadCatalog()`.

- [ ] Tests: match fills qty/unit/price and covers; re-match replaces (1 line, 1 cover); unmatch removes both; `rankFor('portland cement')` puts `Portland Cement 40kg` first.
- [ ] Implement; picker dialog = search field pre-filled with the item description + ranked list (name, code, price/unit, stock); price shown as locked text when `lockPrice`.
- [ ] `flutter analyze` clean; `flutter test test/features/procurement` PASS.

### Task 4: POS auto-refresh (POS Flutter)

**Files:** Modify `hardware_store/flutter/lib/features/requisitions/viewmodels/project_requests_viewmodel.dart`, `hardware_store/flutter/lib/shared/widgets/app_shell.dart`; Test existing viewmodel test file.

**Produces:** `ProjectRequestsViewmodel.startAutoRefresh({Duration every = const Duration(seconds: 15)})`, cancelled in `dispose`; a silent reload skips when `isLoading` or any submission is in flight. AppShell re-runs its marker loads every 15 s while mounted.

- [ ] Test with `fake_async`: after 15 s the repository is read again; no read after dispose.
- [ ] Implement; `flutter analyze` clean; tests PASS.

### Task 5: Live check

- [ ] Restart `cpms_backend`/`cpms_pos_outbox`; as Ramon, open catalogue (15 products), order 2; POS manager on the requests page sees it without action.
