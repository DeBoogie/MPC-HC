[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

$errors = New-Object System.Collections.Generic.List[string]
function Add-Arm64Error([string]$Message) {
    $script:errors.Add($Message)
}

try {
    $solution = Get-Content 'mpc-hc.sln' -Raw
    if ($solution -notmatch '(?m)^\s*Debug Lite\|ARM64 = Debug Lite\|ARM64\s*$') {
        Add-Arm64Error 'Solution is missing Debug Lite|ARM64.'
    }
    if ($solution -notmatch '(?m)^\s*Release Lite\|ARM64 = Release Lite\|ARM64\s*$') {
        Add-Arm64Error 'Solution is missing Release Lite|ARM64.'
    }
    if ($solution -match '(?m)^\s*(Debug|Release)\|ARM64 =') {
        Add-Arm64Error 'ARM64 must remain Lite-only until bundled ARM64 LAV/MPCVR dependencies exist.'
    }

    $projects = @{}
    $projectRegex = [regex]'(?m)^Project\("\{[^}]+\}"\) = "(?<name>[^"]+)", "(?<path>[^"]+\.vcxproj)", "\{(?<guid>[^}]+)\}"'
    foreach ($match in $projectRegex.Matches($solution)) {
        $projects[$match.Groups['guid'].Value.ToUpperInvariant()] = @{
            Name = $match.Groups['name'].Value
            Path = $match.Groups['path'].Value
        }
    }

    $buildRegex = [regex]'(?m)^\s*\{(?<guid>[^}]+)\}\.(?<solutionConfig>Debug Lite|Release Lite)\|ARM64\.Build\.0\s*=\s*(?<projectConfig>[^|]+)\|ARM64\s*$'
    $armBuilds = @($buildRegex.Matches($solution))
    if (-not $armBuilds.Count) {
        Add-Arm64Error 'No ARM64 Build.0 mappings were found.'
    }

    $forbiddenBuildProjects = @('LCDUI', 'minhook', 'LAVFilters')
    foreach ($build in $armBuilds) {
        $guid = $build.Groups['guid'].Value.ToUpperInvariant()
        if (-not $projects.ContainsKey($guid)) {
            Add-Arm64Error "ARM64 Build.0 references unknown project GUID $guid."
            continue
        }
        $project = $projects[$guid]
        if ($forbiddenBuildProjects -contains $project.Name) {
            Add-Arm64Error "ARM64 must not build x86/x64-only project $($project.Name)."
        }
        $path = $project.Path.Replace('\', [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path $path)) {
            Add-Arm64Error "Project file is missing: $path"
            continue
        }
        try { [xml]$xml = Get-Content $path -Raw } catch {
            Add-Arm64Error "Invalid project XML: $path"
            continue
        }
        $projectConfig = $build.Groups['projectConfig'].Value
        if ((Get-Content $path -Raw) -notmatch ('<ProjectConfiguration Include="' + [regex]::Escape($projectConfig) + '\|ARM64">')) {
            Add-Arm64Error "$($project.Name) lacks $projectConfig|ARM64 ProjectConfiguration."
        }
    }

    foreach ($required in @('mpc-hc', 'ffmpeg', 'libass')) {
        $hasBuild = $false
        foreach ($build in $armBuilds) {
            $guid = $build.Groups['guid'].Value.ToUpperInvariant()
            if ($projects.ContainsKey($guid) -and $projects[$guid].Name -eq $required) {
                $hasBuild = $true
                break
            }
        }
        if (-not $hasBuild) { Add-Arm64Error "Required ARM64 project $required is not built." }
    }

    foreach ($entry in $projects.GetEnumerator()) {
        $path = $entry.Value.Path.Replace('\', [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path $path)) { continue }
        try { [xml]$xml = Get-Content $path -Raw } catch { continue }
        $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $ns.AddNamespace('m', 'http://schemas.microsoft.com/developer/msbuild/2003')
        foreach ($node in $xml.SelectNodes('//*[@Condition]', $ns)) {
            if ($node.Condition -notmatch 'ARM64') { continue }
            $text = $node.InnerText
            if ($text -match '(?i)(\\lib64(?:\\|;)|thirdparty\\64\\|\\x64\\)') {
                Add-Arm64Error "ARM64 condition in $path references an x64 prebuilt path: $($node.Condition)"
            }
        }
    }

    $mainProject = Get-Content 'src\mpc-hc\mpc-hc.vcxproj' -Raw
    if ($mainProject -notmatch 'MPC_ARM64_LITE') { Add-Arm64Error 'Main project is missing MPC_ARM64_LITE.' }
    if ($mainProject -notmatch 'LCDUI\\LCDUI\.vcxproj" Condition="''\$\(Platform\)''!=''ARM64''"') {
        Add-Arm64Error 'LCDUI project reference is not excluded from ARM64.'
    }
    if ($mainProject -notmatch 'minhook\\minhook\.vcxproj" Condition="''\$\(Platform\)''!=''ARM64''"') {
        Add-Arm64Error 'MinHook project reference is not excluded from ARM64.'
    }
    $armLiteGroup = [regex]::Match($mainProject, '<ItemDefinitionGroup Condition="\$\(Configuration\.Contains\(''Lite''\)\) and ''\$\(Platform\)''==''ARM64''">(?<body>.*?)</ItemDefinitionGroup>', 'Singleline')
    if (-not $armLiteGroup.Success) {
        Add-Arm64Error 'Main project is missing ARM64 Lite dependency group.'
    } else {
        $deps = $armLiteGroup.Groups['body'].Value
        if ($deps -match '(?i)(LCDUI\.lib|minhook\.lib)') {
            Add-Arm64Error 'ARM64 Lite still links an x86-only LCDUI/MinHook library.'
        }
    }

    [xml]$libassXml = Get-Content 'src\thirdparty\libass\libass.vcxproj' -Raw
    $ns = New-Object System.Xml.XmlNamespaceManager($libassXml.NameTable)
    $ns.AddNamespace('m', 'http://schemas.microsoft.com/developer/msbuild/2003')
    $nasmNodes = @($libassXml.SelectNodes('//m:NASM[@Include]', $ns))
    if (-not $nasmNodes.Count) { Add-Arm64Error 'libass NASM source list is unexpectedly empty.' }
    foreach ($nasm in $nasmNodes) {
        $excluded = @($nasm.SelectNodes('m:ExcludedFromBuild', $ns) | Where-Object { $_.GetAttribute('Condition') -match 'ARM64' -and $_.InnerText -eq 'true' })
        if (-not $excluded.Count) { Add-Arm64Error "libass NASM source is not excluded from ARM64: $($nasm.GetAttribute('Include'))" }
    }
    $libassConfig = Get-Content 'src\thirdparty\libass\config.h' -Raw
    if ($libassConfig -notmatch '(?s)defined\(_M_ARM64\).*?CONFIG_ASM 0.*?ARCH_X86 0') {
        Add-Arm64Error 'libass config does not select the portable C path on ARM64.'
    }

    [xml]$ffmpegXml = Get-Content 'src\thirdparty\ffmpeg\ffmpeg.vcxproj' -Raw
    $ns = New-Object System.Xml.XmlNamespaceManager($ffmpegXml.NameTable)
    $ns.AddNamespace('m', 'http://schemas.microsoft.com/developer/msbuild/2003')
    $armNMake = @($ffmpegXml.SelectNodes('//*[contains(@Condition, "ARM64") and (self::m:NMakeBuildCommandLine or self::m:NMakeReBuildCommandLine or self::m:NMakeCleanCommandLine)]', $ns))
    if (-not $armNMake.Count) {
        Add-Arm64Error 'FFmpeg project has no ARM64 NMake commands.'
    }
    foreach ($node in $armNMake) {
        if ($node.InnerText -notmatch '(?i)ffmpeg\.bat ARM64') {
            Add-Arm64Error "FFmpeg ARM64 command does not use the portable ARM64 mode: $($node.InnerText)"
        }
    }
    $ffmpegMake = Get-Content 'src\thirdparty\ffmpeg\ffmpeg-msvc.mak' -Raw
    if ($ffmpegMake -notmatch 'MPC_FFMPEG_GENERIC_ARM64' -or
        $ffmpegMake -notmatch '(filter_x86|filter-out %/x86/%)' -or
        $ffmpegMake -notmatch 'SRCS_NASM_LC :=') {
        Add-Arm64Error 'FFmpeg ARM64 portable-C filtering is incomplete.'
    }
    $ffmpegConfig = Get-Content 'src\thirdparty\ffmpeg\config.h' -Raw
    if ($ffmpegConfig -notmatch 'MPC_FFMPEG_GENERIC_ARM64' -or $ffmpegConfig -notmatch '#define ARCH_X86 0') {
        Add-Arm64Error 'FFmpeg ARM64 config override is incomplete.'
    }

    $buildScript = Get-Content 'build.bat' -Raw
    foreach ($pattern in @('PPLATFORM=ARM64', 'ARCH=arm64', 'ARM64RequiresLite', 'ARM64" IF DEFINED ASAN')) {
        if ($buildScript -notmatch [regex]::Escape($pattern)) {
            Add-Arm64Error "build.bat is missing ARM64 gate: $pattern"
        }
    }

    foreach ($sourceCheck in @(
        @{ Path='src\DSUtil\Utils.cpp'; Pattern='_M_ARM64' },
        @{ Path='src\SubPic\MemSubPic.cpp'; Pattern='_M_ARM64' },
        @{ Path='src\mpc-hc\ExceptionHandler.cpp'; Pattern='IMAGE_FILE_MACHINE_ARM64' },
        @{ Path='src\DSUtil\MhookHelper.h'; Pattern='MPC_ARM64_NO_MINHOOK' },
        @{ Path='src\mpc-hc\LcdSupport.h'; Pattern='defined\(_M_ARM64\)' }
    )) {
        if ((Get-Content $sourceCheck.Path -Raw) -notmatch $sourceCheck.Pattern) {
            Add-Arm64Error "Missing ARM64 fallback in $($sourceCheck.Path)."
        }
    }

    if ($errors.Count) {
        Write-Host 'ARM64 validation failed:'
        foreach ($item in $errors) { Write-Host " - $item" }
        exit 1
    }

    Write-Host ('ARM64 Lite configuration validated: {0} project build mappings checked.' -f $armBuilds.Count)
}
finally {
    Pop-Location
}
