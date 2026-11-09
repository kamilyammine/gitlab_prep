# Run on a Windows machine WITH internet and Docker Desktop.
# Pulls every image the offline stack needs and saves them into .\images.
#   powershell -ExecutionPolicy Bypass -File scripts\prepare-images.ps1
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

# Minimal .env parser (KEY=VALUE, optional quotes, # comments)
$envVars = @{}
foreach ($line in Get-Content (Join-Path $Root '.env')) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
        $envVars[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
    }
}

$images = @(
    "gitlab/gitlab-ce:$($envVars.GITLAB_VERSION)",
    "gitlab/gitlab-runner:$($envVars.RUNNER_VERSION)",
    "gitlab/gitlab-runner-helper:x86_64-$($envVars.RUNNER_VERSION)"
)
if ($envVars.EXTRA_IMAGES) { $images += ($envVars.EXTRA_IMAGES -split '\s+' | Where-Object { $_ }) }

$imgDir = Join-Path $Root 'images'
New-Item -ItemType Directory -Force $imgDir | Out-Null

foreach ($img in $images) {
    $file = Join-Path $imgDir (($img -replace '[/:]', '_') + '.tar')
    Write-Host ">>> $img"
    docker pull --platform linux/amd64 $img
    if ($LASTEXITCODE -ne 0) { throw "pull failed: $img" }
    docker save $img -o $file
    if ($LASTEXITCODE -ne 0) { throw "save failed: $img" }
}

# Write SHA256SUMS in sha256sum format, LF line endings, no BOM (verified on the VM)
$lines = Get-ChildItem $imgDir -Filter *.tar | Sort-Object Name | ForEach-Object {
    (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower() + '  ' + $_.Name
}
[IO.File]::WriteAllText((Join-Path $imgDir 'SHA256SUMS'), (($lines -join "`n") + "`n"))

Write-Host "`nDone. Images saved in $imgDir"
Get-ChildItem $imgDir | Format-Table Name, @{n='MB';e={[math]::Round($_.Length/1MB)}}
