<#
.SYNOPSIS
    Wipe CPMS database and private_media on the Contabo Windows VPS and re-seed
    with the standard basic demo dataset (company, 6 accounts, master lists,
    4 projects, workers, and Own-Store supplier auto-linked to live POS).

.EXAMPLE
    C:\cpms\scripts\reset-seeded-demo-vps.ps1
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

Write-Host "=== 2/4 Flushing CPMS database & clearing private_media ===" -ForegroundColor Cyan
& $Python manage.py flush --noinput
$MediaDir = Join-Path $BackendDir 'private_media'
if (Test-Path $MediaDir) {
    Remove-Item -Recurse -Force (Join-Path $MediaDir '*') -ErrorAction SilentlyContinue
}

Write-Host "=== 3/4 Seeding basic demo dataset & auto-linking POS payer ===" -ForegroundColor Cyan
& $Python manage.py seed_demo --i-know-this-is-demo --auto-pos-payer

Write-Host "=== 4/4 Verifying POS link & restarting background services ===" -ForegroundColor Cyan
& $Python manage.py check_pos

Stop-Process -Name waitress-serve -Force -ErrorAction SilentlyContinue
schtasks /End /TN BuildPro_CPMS_API 2>$null | Out-Null
schtasks /End /TN BuildPro_CPMS_Outbox 2>$null | Out-Null
Start-Sleep 2
schtasks /Run /TN BuildPro_CPMS_API | Out-Null
schtasks /Run /TN BuildPro_CPMS_Outbox | Out-Null

Write-Host ""
Write-Host "Done! Seeded demo CPMS is live at https://cpms-api.posinventory.space" -ForegroundColor Green
