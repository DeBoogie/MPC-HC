[CmdletBinding()]
param(
    [switch]$Build,
    [switch]$Analyze,
    [switch]$Full
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

try {
    if (Test-Path '.github\workflows') {
        throw 'GitHub Actions workflows are intentionally disabled in this fork. Remove .github/workflows.'
    }

    $requiredFiles = @(
        'src\platform.props',
        'src\common.props',
        'src\thirdparty\LAVFilters\build_ffmpeg.sh',
        'src\thirdparty\LAVFilters\build_lavfilters.bat',
        'distrib\mpc-hc_setup.iss'
    )

    foreach ($file in $requiredFiles) {
        if (-not (Test-Path $file)) {
            throw "Missing required build file: $file"
        }
    }

    [xml](Get-Content 'src\platform.props' -Raw) | Out-Null
    [xml](Get-Content 'src\common.props' -Raw) | Out-Null

    $platform = Get-Content 'src\platform.props' -Raw
    if ($platform -notmatch '>10\.0</WindowsTargetPlatformVersion>') {
        throw 'The default Windows SDK baseline is not Windows 10.'
    }
    if ($platform -notmatch '<PlatformToolset>v143</PlatformToolset>') {
        throw 'The project is not pinned to the VS2022 v143 toolset.'
    }

    $common = Get-Content 'src\common.props' -Raw
    if ($common -notmatch 'WINVER=0x0A00' -or $common -notmatch '_WIN32_WINNT=0x0A00') {
        throw 'The Windows API baseline is older than Windows 10.'
    }
    if ($common -notmatch '<ControlFlowGuard>Guard</ControlFlowGuard>') {
        throw 'Control Flow Guard is not enabled.'
    }

    $installer = Get-Content 'distrib\mpc-hc_setup.iss' -Raw
    if ($installer -notmatch 'MinVersion\s*=\s*10\.0') {
        throw 'The installer still permits pre-Windows-10 systems.'
    }

    & git -c 'core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol' diff --check
    if ($LASTEXITCODE -ne 0) {
        throw 'git diff --check failed.'
    }

    if ($Build -or $Analyze) {
        $buildArgs = @('Build', 'x64', 'MPCHC', 'Release')
        if (-not $Full) {
            $buildArgs += 'Lite'
        }
        if ($Analyze) {
            $buildArgs += 'Analyze'
        }
        $buildArgs += @('Silent', 'Nocolors')

        Write-Host "Running: build.bat $($buildArgs -join ' ')"
        & .\build.bat @buildArgs
        if ($LASTEXITCODE -ne 0) {
            throw "MPC-HC build failed with exit code $LASTEXITCODE."
        }
    }

    Write-Host 'Local modernization checks passed.'
}
finally {
    Pop-Location
}
