[CmdletBinding()]
param(
    [switch]$Lite,
    [switch]$SkipBootstrap,
    [string]$PlaybackManifest = '',
    [string]$OutputDirectory = 'release-output'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    & "$PSScriptRoot\check-build-env.ps1" -Full:(-not $Lite) -Packaging
    if ($LASTEXITCODE -ne 0) { throw 'Build environment validation failed.' }

    if (-not $SkipBootstrap) {
        & "$PSScriptRoot\bootstrap-dependencies.ps1"
        if ($LASTEXITCODE -ne 0) { throw 'Dependency bootstrap failed.' }
    }

    & "$PSScriptRoot\verify-local.ps1"
    if ($LASTEXITCODE -ne 0) { throw 'Repository verification failed.' }

    $args = @('Build', 'x64', 'MPCHC', 'Release')
    if ($Lite) { $args += 'Lite' }
    $args += @('Packages', 'Silent', 'Nocolors')
    Write-Host "Running: build.bat $($args -join ' ')"
    & .\build.bat @args
    if ($LASTEXITCODE -ne 0) { throw "Release build failed with exit code $LASTEXITCODE." }

    if (-not [string]::IsNullOrWhiteSpace($PlaybackManifest)) {
        $playerRelative = if ($Lite) { 'bin\mpc-hc_x64 Lite\mpc-hc64.exe' } else { 'bin\mpc-hc_x64\mpc-hc64.exe' }
        & "$PSScriptRoot\run-playback-tests.ps1" -PlayerPath $playerRelative -ManifestPath $PlaybackManifest
        if ($LASTEXITCODE -ne 0) { throw 'Playback regression suite failed.' }
    }

    $out = Join-Path $repoRoot $OutputDirectory
    if (Test-Path $out) { Remove-Item $out -Recurse -Force }
    New-Item -ItemType Directory -Path $out | Out-Null

    $artifacts = Get-ChildItem (Join-Path $repoRoot 'bin') -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^MPC-HC.*\.(exe|7z)$' }
    if (-not $artifacts) { throw 'Build completed but no release artifacts were found in bin.' }

    $manifestArtifacts = @()
    foreach ($artifact in $artifacts) {
        $dest = Join-Path $out $artifact.Name
        Copy-Item $artifact.FullName $dest
        $manifestArtifacts += [ordered]@{
            name = $artifact.Name
            bytes = (Get-Item $dest).Length
            sha256 = (Get-FileHash $dest -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }

    $releaseManifest = [ordered]@{
        generatedUtc = [DateTime]::UtcNow.ToString('o')
        commit = (& git rev-parse HEAD).Trim()
        branch = (& git branch --show-current).Trim()
        configuration = if ($Lite) { 'x64 Release Lite' } else { 'x64 Release' }
        dependencies = Get-Content 'dependencies\manifest.json' -Raw | ConvertFrom-Json
        artifacts = $manifestArtifacts
    }
    $releaseManifest | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $out 'release-manifest.json') -Encoding UTF8

    Write-Host "Release artifacts written to $out"
}
finally {
    Pop-Location
}
