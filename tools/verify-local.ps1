[CmdletBinding()]
param(
    [ValidateSet('x64', 'ARM64')]
    [string]$Platform = 'x64',
    [switch]$Build,
    [switch]$Analyze,
    [switch]$Sanitize,
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
        'distrib\mpc-hc_setup.iss',
        'dependencies\manifest.json',
        'tools\check-build-env.ps1',
        'tools\bootstrap-dependencies.ps1',
        'tools\release.ps1',
        'tools\mpc-hc-ipc.ps1',
        'docs\JsonIPC.md',
        'docs\AutomatedTesting.md',
        'tools\run-playback-tests.ps1',
        'tools\run-fuzz-smoke.ps1',
        'tests\playback\manifest.example.json',
        'tests\fuzz\corpus\seed.srt',
        'tests\fuzz\corpus\seed.vtt',
        'tests\fuzz\corpus\seed.m3u',
        'src\mpc-hc\PlayerControlService.cpp',
        'src\mpc-hc\PlayerControlService.h',
        'tools\validate-arm64.ps1'
    )

    foreach ($file in $requiredFiles) {
        if (-not (Test-Path $file)) {
            throw "Missing required build file: $file"
        }
    }

    [xml](Get-Content 'src\platform.props' -Raw) | Out-Null
    [xml](Get-Content 'src\common.props' -Raw) | Out-Null

    $platformProps = Get-Content 'src\platform.props' -Raw
    if ($platformProps -notmatch '>10\.0</WindowsTargetPlatformVersion>') {
        throw 'The default Windows SDK baseline is not Windows 10.'
    }
    if ($platformProps -notmatch '<PlatformToolset>v143</PlatformToolset>') {
        throw 'The project is not pinned to the VS2022 v143 toolset.'
    }

    $common = Get-Content 'src\common.props' -Raw
    if ($common -notmatch 'WINVER=0x0A00' -or $common -notmatch '_WIN32_WINNT=0x0A00') {
        throw 'The Windows API baseline is older than Windows 10.'
    }
    if ($common -notmatch '<ControlFlowGuard>Guard</ControlFlowGuard>') {
        throw 'Control Flow Guard is not enabled.'
    }
    if ($common -notmatch '/fsanitize=address') {
        throw 'AddressSanitizer build hook is missing.'
    }

    $solution = Get-Content 'mpc-hc.sln' -Raw
    $mainProject = Get-Content 'src\mpc-hc\mpc-hc.vcxproj' -Raw
    $ffmpegProject = Get-Content 'src\thirdparty\ffmpeg\ffmpeg.vcxproj' -Raw
    $ffmpegMake = Get-Content 'src\thirdparty\ffmpeg\ffmpeg-msvc.mak' -Raw
    if ($solution -notmatch 'Debug Lite\|ARM64' -or $solution -notmatch 'Release Lite\|ARM64' -or
        $mainProject -notmatch 'mpc-hc_ARM64' -or $mainProject -notmatch 'MPC_ARM64_LITE' -or
        $ffmpegProject -notmatch 'ffmpeg\.bat arm64' -or $ffmpegMake -notmatch 'MPC_FFMPEG_GENERIC_ARM64') {
        throw 'Experimental ARM64 Lite build configuration is incomplete.'
    }
    if ($solution -match 'Debug\|ARM64 = Debug\|ARM64' -or $solution -match 'Release\|ARM64 = Release\|ARM64') {
        throw 'ARM64 must remain Lite-only until native bundled LAV/MPCVR dependencies are available.'
    }

    & powershell -ExecutionPolicy Bypass -File tools\validate-arm64.ps1
    if ($LASTEXITCODE -ne 0) {
        throw 'ARM64 structural validation failed.'
    }

    $dependencyManifest = Get-Content 'dependencies\manifest.json' -Raw | ConvertFrom-Json
    if ($dependencyManifest.schemaVersion -ne 1 -or -not $dependencyManifest.components.mpcVideoRenderer.version) {
        throw 'Dependency manifest is invalid.'
    }

    $mainFrame = Get-Content 'src\mpc-hc\MainFrm.cpp' -Raw
    $webClient = Get-Content 'src\mpc-hc\WebClientSocket.cpp' -Raw
    if ($mainFrame -notmatch 'm_playerControlService\.Execute' -or $webClient -notmatch 'ExecutePlayerControlSync') {
        throw 'Shared player control service is not wired into IPC/web control paths.'
    }

    $webServer = Get-Content 'src\mpc-hc\WebServer.cpp' -Raw
    $settingsSource = Get-Content 'src\mpc-hc\AppSettings.cpp' -Raw
    if ($webServer -notmatch '403 Forbidden' -or $webServer -notmatch 'bWebServerAllowCGIOverNetwork' -or $settingsSource -notmatch 'bWebServerAllowCGIOverNetwork\(false\)') {
        throw 'Remote CGI must remain an explicit opt-in with a 403 default deny path.'
    }

    $networkMain = Get-Content 'src\mpc-hc\MainFrm.cpp' -Raw
    $playerControl = Get-Content 'src\mpc-hc\PlayerControlService.cpp' -Raw
    $networkSettings = Get-Content 'src\mpc-hc\AppSettings.cpp' -Raw
    if ($networkMain -notmatch 'ScheduleNetworkRetry' -or $networkMain -notmatch 'NETWORK_RETRY_RESET' -or $playerControl -notmatch 'retry-wait' -or $networkSettings -notmatch 'bNetworkAutoRetry\(true\)') {
        throw 'Network reconnect/state model is incomplete.'
    }

    $installer = Get-Content 'distrib\mpc-hc_setup.iss' -Raw
    if ($installer -notmatch 'MinVersion\s*=\s*10\.0') {
        throw 'The installer still permits pre-Windows-10 systems.'
    }

    & git -c 'core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol' diff --check
    if ($LASTEXITCODE -ne 0) {
        throw 'git diff --check failed.'
    }

    if ($Build -or $Analyze -or $Sanitize) {
        if ($Platform -eq 'ARM64' -and $Sanitize) { throw 'AddressSanitizer is not enabled for the ARM64 target.' }
        $buildArgs = @('Build', $Platform, 'MPCHC', 'Release')
        if ($Platform -eq 'ARM64') {
            if ($Full) { throw 'ARM64 currently supports Lite builds only.' }
            $buildArgs += 'Lite'
        } elseif (-not $Full) {
            $buildArgs += 'Lite'
        }
        if ($Analyze) {
            $buildArgs += 'Analyze'
        }
        if ($Sanitize) {
            $buildArgs += 'ASAN'
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
