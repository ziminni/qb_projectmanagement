<#
.SYNOPSIS
    Reset the local Docker CPMS presentation database. Does not delete upload files.
.EXAMPLE
    .\scripts\reset-presentation.ps1 -Mode Fresh -ConfirmReset
.EXAMPLE
    .\scripts\reset-presentation.ps1 -Mode Demo -ConfirmReset
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Fresh', 'Demo')]
    [string]$Mode,
    [switch]$ConfirmReset
)

$ErrorActionPreference = 'Stop'
if (-not $ConfirmReset) {
    throw 'This wipes the CPMS database. Back it up first, then pass -ConfirmReset for a disposable presentation database only.'
}

Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    docker compose --profile tunnel stop cloudflared pos_outbox backend
    if ($LASTEXITCODE -ne 0) { throw 'Could not stop CPMS services; no reset attempted.' }

    docker compose up -d --wait db
    if ($LASTEXITCODE -ne 0) { throw 'CPMS database did not start; no reset attempted.' }

    $seedOption = if ($Mode -eq 'Fresh') { '--users-only' } else { '--auto-pos-payer' }
    docker compose run --rm --no-deps backend sh -ec "python manage.py migrate --noinput && python manage.py flush --noinput && python manage.py seed_demo --i-know-this-is-demo $seedOption"
    if ($LASTEXITCODE -ne 0) { throw 'CPMS reset failed. Read the error above before restarting services.' }

    docker compose up -d backend pos_outbox
    if ($LASTEXITCODE -ne 0) { throw 'Data seeded, but CPMS services did not start.' }
    Write-Host "CPMS $Mode data seeded. Public CPMS tunnel remains stopped."
    if ($Mode -eq 'Demo') {
        docker compose exec -T backend python manage.py check_pos
        if ($LASTEXITCODE -ne 0) { throw 'Demo data is loaded, but the POS link is not ready. Check the error above before presenting an own-store order.' }
    }
} finally {
    Pop-Location
}
