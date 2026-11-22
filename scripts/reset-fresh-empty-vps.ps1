<#
.SYNOPSIS
    Wipe CPMS database and uploaded private_media on the Contabo Windows VPS to a clean,
    empty testing state (zero projects/materials/workers/reports/VOs) while keeping only
    the company profile, the System Admin account, and the Own-Store supplier auto-linked
    to the live POS contractor payer.

.EXAMPLE
    C:\cpms\scripts\reset-fresh-empty-vps.ps1
#>

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$BackendDir = Join-Path $RepoRoot 'django-backend'
$EnvFile = Join-Path $BackendDir '.env'
$Python = Join-Path $BackendDir '.venv\Scripts\python.exe'

if (!(Test-Path $EnvFile)) {
    throw "Missing $EnvFile"
}

Write-Host "=== 1/4 Loading .env ===" -ForegroundColor Cyan
Get-Content $EnvFile | Where-Object { $_ -match '^[^#].*=' } | ForEach-Object {
    $k, $v = $_ -split '=', 2
    [Environment]::SetEnvironmentVariable($k.Trim(), $v.Trim(), 'Process')
}

Set-Location $BackendDir

Write-Host "=== 2/4 Applying migrations, flushing CPMS DB & clearing private_media ===" -ForegroundColor Cyan
& $Python manage.py migrate --noinput
& $Python manage.py collectstatic --noinput
& $Python manage.py flush --noinput
$MediaDir = Join-Path $BackendDir 'private_media'
if (Test-Path $MediaDir) {
    Remove-Item -Recurse -Force (Join-Path $MediaDir '*') -ErrorAction SilentlyContinue
}

Write-Host "=== 3/4 Seeding company, System Admin account & linking Own-Store POS payer ===" -ForegroundColor Cyan
$py = @'
from apps.users import demo_data
from apps.users.management.commands.seed_demo import Command as SeedCmd
from apps.users.models import Role, User
from apps.master_data.models import Supplier

cmd = SeedCmd()
company = cmd._seed_company()
admin_row = next(row for row in demo_data.USERS if Role.ADMIN in row["roles"])
admin, _ = User.objects.get_or_create(
    email=admin_row["email"],
    defaults={"full_name": admin_row["full_name"], "company": company},
)
admin.full_name = admin_row["full_name"]
admin.phone = admin_row["phone"]
admin.company = company
admin.is_active = True
admin.set_password(demo_data.DEMO_PASSWORD)
admin.save()
admin.set_roles([Role.ADMIN])
payer_id = cmd._discover_pos_payer_id()
Supplier.objects.create(
    name="Own Hardware Store",
    is_own_store=True,
    pos_payer_id=payer_id,
)
print(f"FRESH EMPTY CPMS READY (ADMIN={admin.email}, POS_PAYER_ID={payer_id})")
'@

$py | & $Python manage.py shell

Write-Host "=== 4/4 Verifying POS link & restarting background services ===" -ForegroundColor Cyan
& $Python manage.py check_pos

Stop-Process -Name waitress-serve -Force -ErrorAction SilentlyContinue
schtasks /End /TN BuildPro_CPMS_API 2>$null | Out-Null
schtasks /End /TN BuildPro_CPMS_Outbox 2>$null | Out-Null
Start-Sleep 2
schtasks /Run /TN BuildPro_CPMS_API | Out-Null
schtasks /Run /TN BuildPro_CPMS_Outbox | Out-Null

Write-Host ""
Write-Host "Done! Fresh empty CPMS is live at https://cpms-api.posinventory.space" -ForegroundColor Green
