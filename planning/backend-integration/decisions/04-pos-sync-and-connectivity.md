# Own-store PO sync to POS and HTTPS/tunnel connectivity

**Status:** Locked (revisable if build-time edge cases arise).
**Choice:** Trigger POS requisition sync when an Owner/PM places an Own-Store `PurchaseOrder` (`MaterialSource.ownStore`), using outbound HTTPS (`POS_API_BASE_URL` via LAN/localhost or Cloudflare Tunnel / Tailscale) plus a durable retry queue in CPMS. (by: me)

## Context & Verified Findings

1. **CPMS Procurement flow (`MockProcurementRepository`):**
   - `site_engineer` creates a `MaterialRequest` (`MR-0001`) with `SiteCount`s.
   - `owner` (Owner / PM) fulfills it by creating a `PurchaseOrder` (`PO-2026-0001`):
     - `MaterialSource.ownStore`: orders from the hardware store (`status = released`).
     - `MaterialSource.otherStore`: logs an external purchase with `storeName`, `orNumber`, and `receiptPhotoUrl` (`status = purchased`) — stays 100% inside CPMS.
2. **Actual POS Integration Contract (`qb_pos_inventory_system` at `3791279`):**
   - Authenticated via JWT belonging to a user in the `CPMS Service` group (`IsCPMSService` permission; 8h access / 7d rotating refresh).
   - Six endpoints under `/api/v1/integration/cpms/`:
     - `GET /api/v1/integration/cpms/customers/` → `{id, name}` (CONTRACTOR / CONSTRUCTION_FIRM)
     - `GET /api/v1/integration/cpms/materials/` → `{code, product, unit}` (selling-unit barcode)
     - `POST /api/v1/integration/cpms/requests/` → idempotent on `cpms_request_id` + UUID `token`
     - `GET /api/v1/integration/cpms/requests/{cpms_request_id}/` → `{status, decline_reason, expected_amount, items: [{code, requested, released, outstanding, available, decline_reason}]}`
     - `POST /api/v1/integration/cpms/requests/{cpms_request_id}/close/`
     - `GET /api/v1/integration/cpms/projects/{cpms_project_id}/payables/` → `{cpms_project_id, total, paid, balance}`

## Locked Rules

1. **When POS sync fires:**
   - Only `PurchaseOrder`s with `source == 'own_store'` sync to POS.
   - Before calling POS, CPMS atomically saves the `PurchaseOrder` with:
     - `pos_request_id = po.po_no` (e.g. `PO-2026-0001`)
     - `pos_token = str(uuid4())` (minted once, never regenerated on retry)
     - `pos_sync_status = 'pending_sync'`
   - CPMS `PosAPIClient` posts to `POST /api/v1/integration/cpms/requests/` with `cpms_request_id = po.po_no`, `token = po.pos_token`, `project = {cpms_project_id: project.code, name: project.name, payer: project.pos_payer_id}`, `requester_name`, `approver_name`, and `items = [{code: item.pos_code, quantity: str(item.quantity)}]`.
   - On HTTP 200/201, `pos_sync_status` becomes `'synced'`. On network/timeout error (e.g. store internet down), the PO remains saved with `pos_sync_status = 'pending_sync'` and can be retried manually ("Retry POS sync") or by a background/on-read retry hook using the **exact same** `pos_request_id` and `pos_token`.
2. **Read-back & cancellation:**
   - Viewing an Own-Store PO or refreshing POS status calls `GET /api/v1/integration/cpms/requests/{po_no}/` to update `pos_status` (`WAITING`, `ACCEPTED`, `DECLINED`, `PARTIAL`, `RELEASED`, `CLOSED`), `pos_expected_amount`, and per-line released quantities.
   - Cancelling an Own-Store PO in CPMS (before site delivery) calls `POST /api/v1/integration/cpms/requests/{po_no}/close/` on POS.
3. **Network topology between Cloud CPMS and Local POS:**
   - CPMS connects to `POS_API_BASE_URL` over HTTPS (configurable via env var / Admin Settings).
   - For local/LAN defense: `POS_API_BASE_URL` points to the POS container/host (`http://127.0.0.1:8000` or LAN IP).
   - For cloud CPMS + local store POS: expose the store's POS API via a free **Cloudflare Tunnel (`cloudflared`)** or **Tailscale** so Cloud CPMS reaches `/api/v1/integration/cpms/*` securely without router port-forwarding or rewriting POS.
