[CmdletBinding()]
param(
    [switch]$Full,
    [switch]$Packaging
)

$ErrorActionPreference = 'Stop'
$missing = New-Object System.Collections.Generic.List[string]

function Write-Check([bool]$Ok, [string]$Name, [string]$Detail = '') {
    $prefix = if ($Ok) { '[OK]  ' } else { '[FAIL]' }
    $suffix = if ($Detail) { " - $Detail" } else { '' }
    Write-Host "$prefix $Name$suffix"
    if (-not $Ok) { $script:missing.Add($Name) }
}

function Find-CommandPath([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

Write-Host 'MPC-HC build environment'
Write-Host '------------------------'

$git = Find-CommandPath 'git.exe'
Write-Check ([bool]$git) 'Git' $git

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsRequirements = @(
    @{ Id = 'Microsoft.Component.MSBuild'; Name = 'MSBuild' },
    @{ Id = 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'; Name = 'MSVC x86/x64 tools' },
    @{ Id = 'Microsoft.VisualStudio.Component.VC.ATLMFC'; Name = 'C++ ATL/MFC' }
)

$usableVs = $null
if (Test-Path $vswhere) {
    $allIds = @($vsRequirements | ForEach-Object { $_.Id })
    $usableVs = (& $vswhere -latest -products '*' -requires $allIds -property installationPath 2>$null | Select-Object -First 1)
    Write-Check ([bool]$usableVs) 'Visual Studio C++ toolchain' $usableVs
    if (-not $usableVs) {
        foreach ($req in $vsRequirements) {
            $path = (& $vswhere -latest -products '*' -requires $req.Id -property installationPath 2>$null | Select-Object -First 1)
            Write-Check ([bool]$path) $req.Name $path
        }
        Write-Host '      No single Visual Studio installation contains all required components.'
    }
} else {
    Write-Check $false 'Visual Studio Installer (vswhere.exe)' $vswhere
}

$sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Include'
$sdkVersion = $null
if (Test-Path $sdkRoot) {
    $sdkVersion = Get-ChildItem $sdkRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^10\.0\.' } |
        Sort-Object { [version]$_.Name } -Descending |
        Select-Object -First 1 -ExpandProperty Name
}
Write-Check ([bool]$sdkVersion) 'Windows 10/11 SDK' $sdkVersion

$nasm = Find-CommandPath 'nasm.exe'
Write-Check ([bool]$nasm) 'NASM' $nasm

if ($Full) {
    $msysRoot = if ($env:MPCHC_MSYS) { $env:MPCHC_MSYS } else { 'C:\msys64' }
    $mingw64 = if ($env:MPCHC_MINGW64) { $env:MPCHC_MINGW64 } else { Join-Path $msysRoot 'mingw64' }
    $bash = Join-Path $msysRoot 'usr\bin\bash.exe'
    $gcc = Join-Path $mingw64 'bin\x86_64-w64-mingw32-gcc.exe'
    if (-not (Test-Path $gcc)) { $gcc = Join-Path $mingw64 'bin\gcc.exe' }
    Write-Check (Test-Path $bash) 'MSYS2 bash' $bash
    Write-Check (Test-Path $gcc) 'MinGW-w64 x64 GCC' $gcc
}

if ($Packaging) {
    $sevenZip = Find-CommandPath '7z.exe'
    if (-not $sevenZip) { $sevenZip = Find-CommandPath '7za.exe' }
    if (-not $sevenZip) {
        foreach ($candidate in @(
            (Join-Path $env:ProgramFiles '7-Zip\7z.exe'),
            (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe')
        )) {
            if (Test-Path $candidate) { $sevenZip = $candidate; break }
        }
    }
    Write-Check ([bool]$sevenZip) '7-Zip' $sevenZip

    $inno = $null
    foreach ($regPath in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1',
        'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1'
    )) {
        $item = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
        if ($item.'Inno Setup: App Path') {
            $candidate = Join-Path $item.'Inno Setup: App Path' 'ISCC.exe'
            if (Test-Path $candidate) { $inno = $candidate; break }
        }
    }
    Write-Check ([bool]$inno) 'Inno Setup 6' $inno
}

if ($missing.Count) {
    Write-Host ''
    Write-Host ('Missing {0} required item(s): {1}' -f $missing.Count, ($missing -join ', '))
    Write-Host 'See docs\Compilation.md for installation instructions.'
    exit 1
}

Write-Host ''
Write-Host 'Build environment is ready.'
