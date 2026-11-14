# WBS categories, verified to-do progress, and derived project costing

**Status:** Locked (revisable if build-time edge cases arise).
**Choice:** Adopt the frontend's `Category` (budget-weighted) + verified `Todo` formula for WBS/progress, derive project actual costs from confirmed Deliveries + processed Payroll + approved Equipment hours, and use barcode mapping + POS read-back (`expected_amount` & project payables) with clean extension hooks for POS Phase 1c. (by: me)

## Locked Rules

1. **WBS, Gantt, and Progress (`Category` + `Todo`):**
   - Replace the legacy backend `ProjectPhase` / `Milestone` mismatch with the frontend's `Category` (`project_id`, `name`, `budget`, `sort_order`) and `Todo` (`category_id`, `title`, `start_date`, `end_date`, `is_done`, `done_by`, `done_at`, `daily_report_id`, `verified_by`, `verified_at`) — keys per Flutter `todo.dart` (corrected by [Phase 2 contract rulings](./06-phase-2-contract-rulings.md)).
   - Progress is computed deterministically via the `computeProjectProgress` rules:
     - Only Owner-verified to-dos (`verified_at != null`) count toward `categoryProgress = verifiedTodos / totalTodos`.
     - When every category has a positive `budget`, `weight = category.budget / totalBudget` (budget-weighted progress, matching the manuscript's weighted phase requirement); otherwise equal weights (`1 / N`).
     - `earnedValue = progress * contractAmount` feeds both Financials and Progress Billing (`asOf = periodEnd`).
2. **Authoritative Project Actual Costing (no double counting):**
   - Project actual costs are derived from three auditable operational sources (`ProjectCostService`):
     - **Materials:** `sum(DeliveryItem.qty_good * PurchaseOrderItem.unit_price)` grouped by `PurchaseOrder.category_id`.
     - **Labor:** gross pay from `PayrollPeriod` rows (`status == 'processed'`) for the project.
     - **Equipment:** `sum(EquipmentLog.hours_used * EquipmentItem.hourly_rate)` from `DailyReport`s with `status == 'approved'`.
   - Site inventory on hand is computed via `computeSiteInventory` (`delivered qty_good` minus `approved DailyReport MaterialUsage`).
3. **POS Catalog Mapping, Pricing & Payables (upgradeable to Phase 1c):**
   - CPMS Master Data `MaterialItem` stores `pos_code` (nullable selling-unit barcode from POS `GET /api/v1/integration/cpms/materials/`) alongside `name`, `unit`, and `unit_price`.
   - Own-store `PurchaseOrder` stores `pos_request_id`, `pos_token`, `pos_sync_status`, `pos_status`, and `pos_expected_amount` (from POS read-back).
   - CPMS `SupplierPayment` stores `external_ref` and `receipt_photo_url`.
   - **Forward-compatible upgrade path:** Because all mapping and receipt columns exist in CPMS from day one, enabling POS Phase 1c later (pushing payment receipt photos to POS and pulling unit prices from POS `/integration/cpms/materials/`) is a purely additive change in `PosAPIClient` with zero CPMS schema or UI breakage.
