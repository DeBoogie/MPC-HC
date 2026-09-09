[CmdletBinding()]
param(
    [switch]$Force,
    [string]$CacheDirectory = 'build\dependency-cache'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repoRoot 'dependencies\manifest.json'
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$cacheRoot = Join-Path $repoRoot $CacheDirectory
New-Item -ItemType Directory -Force -Path $cacheRoot | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-VerifiedArchive($package) {
    $leaf = Split-Path ([uri]$package.url).AbsolutePath -Leaf
    $cachePath = Join-Path $cacheRoot ("{0}-{1}" -f $package.architecture, $leaf)
    $expected = $package.sha256.ToLowerInvariant()

    if ((Test-Path $cachePath) -and -not $Force) {
        $actual = (Get-FileHash $cachePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -eq $expected) { return $cachePath }
        Remove-Item $cachePath -Force
    }

    Write-Host "Downloading $($package.architecture) dependency archive..."
    Invoke-WebRequest -UseBasicParsing -Uri $package.url -OutFile $cachePath
    $actual = (Get-FileHash $cachePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        Remove-Item $cachePath -Force -ErrorAction SilentlyContinue
        throw "SHA-256 mismatch for $($package.url). Expected $expected, got $actual."
    }
    return $cachePath
}

$component = $manifest.components.mpcVideoRenderer
foreach ($package in $component.packages) {
    $archive = Get-VerifiedArchive $package
    $destination = Join-Path $repoRoot $package.destination
    New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null

    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq $package.archivePath } | Select-Object -First 1
        if (-not $entry) { throw "Archive entry '$($package.archivePath)' was not found in $archive." }
        $tmp = "$destination.tmp"
        $input = $entry.Open()
        $output = [IO.File]::Open($tmp, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }
        Move-Item $tmp $destination -Force
    }
    finally { $zip.Dispose() }

    $version = (Get-Item $destination).VersionInfo.FileVersion
    if ($version -ne $component.version) {
        Remove-Item $destination -Force -ErrorAction SilentlyContinue
        throw "Unexpected MPC Video Renderer version in $destination. Expected $($component.version), got $version."
    }
    Write-Host "[OK] $($package.architecture) MPC Video Renderer $version -> $($package.destination)"
}

Write-Host 'External runtime dependencies are ready.'
