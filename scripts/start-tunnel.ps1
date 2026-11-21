param(
    [string]$Token = "",
    [string]$Hostname = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$EnvDir = Join-Path $RepoRoot "tunnel"
$EnvFile = Join-Path $EnvDir "cloudflared.env"

if ($Token -ne "") {
    if (-not (Test-Path $EnvDir)) {
        New-Item -ItemType Directory -Force -Path $EnvDir | Out-Null
    }
    $lines = @(
        "CLOUDFLARE_TUNNEL_TOKEN=$Token"
    )
    if ($Hostname -ne "") {
        $lines += "CLOUDFLARE_TUNNEL_HOSTNAME=$Hostname"
    }
    Set-Content -Path $EnvFile -Value $lines -Encoding UTF8
    Write-Host "Saved Named Tunnel settings to tunnel/cloudflared.env (gitignored)." -ForegroundColor Green
}

# Load saved Named Tunnel config if present
if (Test-Path $EnvFile) {
    foreach ($line in Get-Content $EnvFile) {
        if ($line -match '^\s*([^#=]+?)\s*=\s*(.+?)\s*$') {
            $k = $Matches[1].Trim()
            $v = $Matches[2].Trim()
            if ($k -eq "CLOUDFLARE_TUNNEL_TOKEN" -and $Token -eq "") { $Token = $v }
            if ($k -eq "CLOUDFLARE_TUNNEL_HOSTNAME" -and $Hostname -eq "") { $Hostname = $v }
        }
    }
}

if ($Token -ne "") {
    $env:CLOUDFLARE_TUNNEL_TOKEN = $Token
    $env:CLOUDFLARED_TUNNEL_ARGS = "run"
    Write-Host "Starting CPMS stack + Cloudflare Named Tunnel..." -ForegroundColor Cyan
} else {
    $env:CLOUDFLARE_TUNNEL_TOKEN = ""
    $env:CLOUDFLARED_TUNNEL_ARGS = "--url http://backend:8001"
    Write-Host "Starting CPMS stack + Cloudflare Quick Tunnel (temporary URL)..." -ForegroundColor Cyan
}

docker compose --profile tunnel up -d --build

$publicUrl = ""
if ($Token -ne "") {
    if ($Hostname -ne "") {
        $publicUrl = "https://$($Hostname -replace '^https?://', '')"
    } else {
        $publicUrl = "https://<your-cloudflare-cpms-hostname>"
    }
} else {
    Write-Host "Waiting for Quick Tunnel URL from cpms_cloudflared..." -ForegroundColor Yellow
    for ($i = 0; $i -lt 30; $i++) {
        $logs = docker logs cpms_cloudflared 2>&1 | Out-String
        if ($logs -match 'https://[a-z0-9-]+\.trycloudflare\.com') {
            $publicUrl = $Matches[0]
            break
        }
        Start-Sleep -Seconds 1
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " CPMS Backend Online URL:" -ForegroundColor Green
if ($publicUrl -ne "") {
    Write-Host "   $publicUrl" -ForegroundColor White
    Write-Host ""
    Write-Host " Run CPMS Flutter app from ANY computer:" -ForegroundColor Cyan
    Write-Host "   cd flutter"
    Write-Host "   flutter run -d windows --dart-define=API_BASE_URL=$publicUrl/api/v1"
    Write-Host "   flutter run -d macos   --dart-define=API_BASE_URL=$publicUrl/api/v1"
    Write-Host "   flutter run -d chrome  --dart-define=API_BASE_URL=$publicUrl/api/v1"
} else {
    Write-Host "   (Timed out waiting for URL; run 'docker logs cpms_cloudflared')" -ForegroundColor Yellow
}
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Checking CPMS -> POS connection (manage.py check_pos)..." -ForegroundColor Cyan
docker compose exec backend python manage.py check_pos
