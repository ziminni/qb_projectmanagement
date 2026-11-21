# BuildPro Ecosystem — Daily Operations & Update Guide

This guide covers the two everyday workflows for running the full 3-device **BuildPro** ecosystem (**Contabo VPS CPMS** + **Windows POS & Inventory** + **Android Bodega Mobile**):

1. [Part 1 — Starting From Complete Shutdown](#part-1--starting-from-complete-shutdown)
2. [Part 2 — Updating After Pushing Code Changes](#part-2--updating-after-pushing-code-changes)

---

## Live Architecture & Endpoints

| System | Host | Public HTTPS URL | Branch |
|---|---|---|---|
| **CPMS** | Contabo Windows Server VPS (24/7 native Windows + Cloudflare Named Tunnel) | `https://cpms-api.posinventory.space` | `main` |
| **POS & Inventory** | Store Windows PC (Docker + Cloudflare Named Tunnel) | `https://pos-api.posinventory.space` | `master` |
| **Bodega Mobile** | Android Phone (Pre-baked APK) | Connects to `https://pos-api.posinventory.space` | `master` |

---

## Part 1 — Starting From Complete Shutdown

### 1. Windows Laptop (POS & Inventory Server + Desktop App)
1. **Open Docker Desktop** and wait until it finishes starting (green status).
2. Open **PowerShell** inside the POS repo (`hardware_store` / `qb_pos_inventory_system`) and pull latest code:
   ```powershell
   git checkout master; git pull origin master
   ```
3. **Choose your database mode:**
   - **Keep existing data (normal daily start):**
     ```powershell
     curl.exe -s https://pos-api.posinventory.space/api/health/
     ```
     *(Expected: `{"status":"ok"}`. If not, run `.\scripts\start-tunnel.ps1`.)*
   - **Fresh Empty reset** *(only the 6 accounts, `Store`/`Bodega` shelves, 12 standard UOMs & 1 contractor payer — zero products/sales/POs)*:
     ```powershell
     .\scripts\reset-fresh-empty.ps1
     ```
   - **Basic Seeded Demo reset** *(accounts + sample hardware products, stock, suppliers & contractor)*:
     ```powershell
     .\scripts\reset-seeded-demo.ps1
     ```
4. *(Optional — only when testing offline Bodega SMS)* Plug in the USB SIM800C modem and run `python scripts\sms_bridge\sms_bridge.py` in a second PowerShell window.
5. **Run the POS Desktop App:**
   ```powershell
   cd flutter
   flutter pub get
   flutter run -d windows
   ```

---

### 2. Contabo Windows VPS (CPMS Server — Runs 24/7)
- **Normal daily start (keeping existing data):** Do **nothing** — `PostgreSQL 15`, `BuildPro_CPMS_API`, `BuildPro_CPMS_Outbox`, `cloudflared`, and `CPMS_AutoDeploy` run 24/7 in the background even when RDP is closed.
- **Only if you reset POS in Step 1** and want CPMS wiped to match, RDP into the Contabo VPS, open **PowerShell (Administrator)**, and run **one**:
  - **Fresh Empty CPMS:**
    ```powershell
    cd C:\cpms; git pull; .\scripts\reset-fresh-empty-vps.ps1
    ```
  - **Basic Seeded Demo CPMS:**
    ```powershell
    cd C:\cpms; git pull; .\scripts\reset-seeded-demo-vps.ps1
    ```
  - Close RDP once `check_pos` prints **`READY`**. *(Always run the POS reset before the CPMS VPS reset so CPMS auto-links cleanly to the freshly created POS contractor payer.)*

---

### 3. Mac / Windows Dev Laptop (CPMS Flutter App — No Docker Needed)
Open **Terminal** inside `qb_project_management_system`:
```bash
git checkout main
git pull origin main
cd flutter
flutter pub get
flutter run --dart-define=API_BASE_URL=https://cpms-api.posinventory.space/api/v1
```
*(Demo accounts: `maria@example.ph`, `ramon@example.ph`, `ana@example.ph`, `liza@example.ph`, `mark@example.ph`, `elena@example.ph`.)*

---

### 4. Android Phone (Bodega Mobile App)
- **Normal days (no reset, no mobile code change):** Just open **BuildPro POS** on the phone.
- **After any POS database reset:** On the phone open **Settings → Apps → BuildPro POS → Storage → Clear storage**, then sign in as `checker` / `demo1234`.
- **First time or after mobile code changes:** Build the pre-baked APK from the POS repo `flutter` folder:
  ```powershell
  flutter build apk --release --dart-define=API_BASE_URL=https://pos-api.posinventory.space --dart-define=API_GATEWAY_KEY=<your-48-char-QB_GATEWAY_KEY>
  ```
  Install `flutter\build\app\outputs\flutter-apk\app-release.apk` onto the phone.

---

## Part 2 — Updating After Pushing Code Changes

### A. When CPMS (`qb_projectmanagement` / `main`) Changes Are Pushed
1. **Contabo VPS Server (Automatic):**
   - `CPMS_AutoDeploy` checks `origin/main` every **2 minutes**.
   - **Flutter UI-only push (`flutter/`):** Pulled silently with zero API downtime.
   - **Backend push (`django-backend/`):** Automatically installs any new `requirements.txt` packages, runs `migrate --noinput` + `collectstatic --noinput`, restarts `BuildPro_CPMS_API` & `BuildPro_CPMS_Outbox`, and logs to `C:\cpms\deploy.log`.
   - *(Need it immediately instead of waiting 2 minutes? Run `powershell -NoProfile -Ep Bypass -File C:\cpms\auto-deploy.ps1` on the VPS.)*
2. **Mac / Windows CPMS Flutter App:**
   ```bash
   git checkout main
   git pull origin main
   cd flutter
   flutter pub get
   flutter run --dart-define=API_BASE_URL=https://cpms-api.posinventory.space/api/v1
   ```

---

### B. When POS (`qb_hardwarestore` / `master`) Changes Are Pushed
On your **Windows POS PC** (PowerShell inside the POS repo):
1. Pull latest `master`:
   ```powershell
   git checkout master; git pull origin master
   ```
2. **If `backend_django/` changed** (models, views, migrations, requirements):
   ```powershell
   docker compose up -d --build backend
   ```
3. **If `flutter/` desktop UI changed:**
   ```powershell
   cd flutter; flutter pub get; flutter run -d windows
   ```
4. **If `flutter/` Bodega mobile UI changed:**
   Rebuild and reinstall the APK using the `flutter build apk --release ...` command in Step 4 above.

---

### Quick Health Verification (From Any Browser or Terminal)
- **CPMS:** `https://cpms-api.posinventory.space/api/health/` → `{"status":"ok","service":"BuildPro CPMS","system":"cpms"}`
- **POS:** `https://pos-api.posinventory.space/api/health/` → `{"status":"ok"}`
