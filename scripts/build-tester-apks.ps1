param(
    [string]$BuildName = '1.0.1',
    [int]$BuildNumber = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$distDirectory = Join-Path $repoRoot 'dist'
$primaryApi = 'https://api.sakaygaray.com/api/v1'
$fallbackApi = 'https://paragosakay-app-qulmw.ondigitalocean.app/api/v1'
$apiCandidates = "$primaryApi,$fallbackApi"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter is not available on PATH.'
}

New-Item -ItemType Directory -Path $distDirectory -Force | Out-Null

$applications = @(
    @{
        Name = 'Passenger'
        Project = Join-Path $repoRoot 'parago_passenger'
    },
    @{
        Name = 'Driver'
        Project = Join-Path $repoRoot 'parago_mobile'
    }
)

foreach ($application in $applications) {
    Write-Host "Building SAKAY $($application.Name) $BuildName ($BuildNumber)..."
    Push-Location $application.Project
    try {
        flutter pub get
        if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }

        flutter build apk --release `
            --build-name=$BuildName `
            --build-number=$BuildNumber `
            --dart-define=PARAGO_API_BASE_URL=$primaryApi `
            --dart-define=PARAGO_API_BASE_URLS=$apiCandidates `
            --dart-define=PARAGO_ENABLE_REALTIME=true
        if ($LASTEXITCODE -ne 0) { throw 'flutter build apk failed.' }
    }
    finally {
        Pop-Location
    }

    $source = Join-Path $application.Project 'build\app\outputs\flutter-apk\app-release.apk'
    $fileName = "SAKAY-$($application.Name)-Tester-v$BuildName-build$BuildNumber-AWS-DO-Fallback.apk"
    $destination = Join-Path $distDirectory $fileName
    Copy-Item -LiteralPath $source -Destination $destination -Force
    $hash = Get-FileHash -LiteralPath $destination -Algorithm SHA256
    Write-Host "$fileName SHA-256: $($hash.Hash)"
}

Write-Host "Tester APKs written to $distDirectory"
