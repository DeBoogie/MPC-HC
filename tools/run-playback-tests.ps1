[CmdletBinding()]
param(
    [string]$PlayerPath = 'bin\mpc-hc_x64\mpc-hc64.exe',
    [string]$ManifestPath = 'tests\playback\manifest.json',
    [string]$OutputPath = 'build\test-results\playback.json',
    [int]$StartupTimeoutMs = 10000,
    [int]$OpenTimeoutMs = 15000,
    [int]$SeekTimeoutMs = 8000,
    [double]$SeekToleranceSeconds = 0.75,
    [switch]$ValidateManifestOnly
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-RepoPath([string]$Path) {
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

function Test-PlaybackManifest($manifest) {
    if ($manifest.schemaVersion -ne 1) { throw 'Playback manifest schemaVersion must be 1.' }
    if ($null -eq $manifest.cases -or @($manifest.cases).Count -eq 0) { throw 'Playback manifest must contain at least one case.' }
    $names = @{}
    foreach ($case in @($manifest.cases)) {
        if ([string]::IsNullOrWhiteSpace([string]$case.name)) { throw 'Every playback case needs a name.' }
        if ($names.ContainsKey([string]$case.name)) { throw "Duplicate playback case name: $($case.name)" }
        $names[[string]$case.name] = $true
        if ([string]::IsNullOrWhiteSpace([string]$case.path)) { throw "Playback case '$($case.name)' needs a path." }
        foreach ($position in @($case.seekPositions)) {
            if ([double]$position -lt 0) { throw "Playback case '$($case.name)' has a negative seek position." }
        }
        if ($null -ne $case.maxDroppedFrames -and [int]$case.maxDroppedFrames -lt 0) {
            throw "Playback case '$($case.name)' has a negative maxDroppedFrames."
        }
    }
}

function Connect-MpcPipe([int]$ProcessId, [int]$TimeoutMs) {
    $pipe = [System.IO.Pipes.NamedPipeClientStream]::new(
        '.', "MPC-HC-json-$ProcessId", [System.IO.Pipes.PipeDirection]::InOut,
        [System.IO.Pipes.PipeOptions]::None)
    try {
        $pipe.Connect($TimeoutMs)
        $utf8 = [Text.UTF8Encoding]::new($false)
        $connection = [pscustomobject]@{
            Pipe = $pipe
            Writer = [IO.StreamWriter]::new($pipe, $utf8, 4096, $true)
            Reader = [IO.StreamReader]::new($pipe, $utf8, $false, 4096, $true)
            NextId = 1
        }
        $connection.Writer.AutoFlush = $true
        return $connection
    }
    catch {
        $pipe.Dispose()
        throw
    }
}

function Close-MpcPipe($connection) {
    if ($null -eq $connection) { return }
    $connection.Writer.Dispose()
    $connection.Reader.Dispose()
    $connection.Pipe.Dispose()
}

function Invoke-MpcRequest($connection, [string]$Method, [hashtable]$Params = @{}, [int]$TimeoutMs = 10000) {
    $id = $connection.NextId
    $connection.NextId++
    $request = [ordered]@{ id = $id; method = $Method; params = $Params }
    $connection.Writer.WriteLine(($request | ConvertTo-Json -Depth 12 -Compress))
    $task = $connection.Reader.ReadLineAsync()
    if (-not $task.Wait($TimeoutMs)) { throw "Timed out waiting for response to $Method." }
    if ($null -eq $task.Result) { throw "MPC-HC closed the pipe during $Method." }
    $response = $task.Result | ConvertFrom-Json
    if ($null -ne $response.error) { throw "$Method failed ($($response.error.code)): $($response.error.message)" }
    return $response.result
}

function Wait-PlayerState($connection, [scriptblock]$Predicate, [int]$TimeoutMs, [string]$Description) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $last = $null
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        $last = Invoke-MpcRequest $connection 'player.getState' @{} ([Math]::Min(3000, $TimeoutMs))
        if (& $Predicate $last) {
            return [pscustomobject]@{ State = $last; ElapsedMs = [int]$sw.ElapsedMilliseconds }
        }
        Start-Sleep -Milliseconds 100
    }
    throw "Timed out waiting for $Description. Last state: $($last.state), position=$($last.position), duration=$($last.duration)."
}

$manifestFullPath = Resolve-RepoPath $ManifestPath
if (-not (Test-Path $manifestFullPath -PathType Leaf)) { throw "Playback manifest not found: $manifestFullPath" }
$manifest = Get-Content $manifestFullPath -Raw | ConvertFrom-Json
Test-PlaybackManifest $manifest
if ($ValidateManifestOnly) {
    Write-Host "Playback manifest is valid: $manifestFullPath"
    exit 0
}

$playerFullPath = Resolve-RepoPath $PlayerPath
if (-not (Test-Path $playerFullPath -PathType Leaf)) { throw "MPC-HC executable not found: $playerFullPath" }
$manifestDir = Split-Path -Parent $manifestFullPath
$results = New-Object System.Collections.Generic.List[object]

foreach ($case in @($manifest.cases)) {
    $caseErrors = New-Object System.Collections.Generic.List[string]
    $seekResults = New-Object System.Collections.Generic.List[object]
    $process = $null
    $connection = $null
    $casePath = if ([IO.Path]::IsPathRooted([string]$case.path)) {
        [IO.Path]::GetFullPath([string]$case.path)
    } else {
        [IO.Path]::GetFullPath((Join-Path $manifestDir ([string]$case.path)))
    }

    $caseResult = [ordered]@{
        name = [string]$case.name
        path = $casePath
        passed = $false
        startupMs = $null
        mediaReadyMs = $null
        firstFrameMs = $null
        durationSeconds = $null
        seeks = $seekResults
        diagnostics = $null
        errors = $caseErrors
    }

    if (-not (Test-Path $casePath -PathType Leaf)) {
        $caseErrors.Add("Media sample not found: $casePath")
        $results.Add([pscustomobject]$caseResult)
        continue
    }

    try {
        $startup = [Diagnostics.Stopwatch]::StartNew()
        $process = Start-Process -FilePath $playerFullPath -ArgumentList @('/new','/minimized','/nofocus') -PassThru
        $connection = Connect-MpcPipe $process.Id $StartupTimeoutMs
        $caseResult.startupMs = [int]$startup.ElapsedMilliseconds

        $baseline = Invoke-MpcRequest $connection 'player.getDiagnostics'
        $baselineFrames = -1
        if ($null -ne $baseline.renderer -and $null -ne $baseline.renderer.framesDrawn) {
            $baselineFrames = [int]$baseline.renderer.framesDrawn
        }
        $openTimer = [Diagnostics.Stopwatch]::StartNew()
        Invoke-MpcRequest $connection 'player.open' @{ path = $casePath } | Out-Null
        $ready = Wait-PlayerState $connection { param($s) $s.state -ne 'closed' -and [double]$s.duration -ge 0 } $OpenTimeoutMs 'media load'
        $caseResult.mediaReadyMs = [int]$openTimer.ElapsedMilliseconds
        Invoke-MpcRequest $connection 'player.play' | Out-Null

        $frameTimer = [Diagnostics.Stopwatch]::StartNew()
        $firstFrame = $null
        while ($frameTimer.ElapsedMilliseconds -lt $OpenTimeoutMs) {
            $d = Invoke-MpcRequest $connection 'player.getDiagnostics'
            if (($null -ne $d.renderer.framesDrawn -and [int]$d.renderer.framesDrawn -gt $baselineFrames) -or
                    ($null -eq $d.renderer.framesDrawn -and $d.state -eq 'playing')) {
                $firstFrame = $d
                $caseResult.firstFrameMs = [int]$openTimer.ElapsedMilliseconds
                break
            }
            Start-Sleep -Milliseconds 100
        }
        if ($null -eq $firstFrame) { $caseErrors.Add('No rendered/playing frame was observed before the open timeout.') }

        $state = Invoke-MpcRequest $connection 'player.getState'
        $caseResult.durationSeconds = [double]$state.duration
        if ($null -ne $case.minDurationSeconds -and [double]$state.duration -lt [double]$case.minDurationSeconds) {
            $caseErrors.Add("Duration $($state.duration)s is below required $($case.minDurationSeconds)s.")
        }

        foreach ($position in @($case.seekPositions)) {
            $target = [double]$position
            $seekTimer = [Diagnostics.Stopwatch]::StartNew()
            Invoke-MpcRequest $connection 'player.seek' @{ position = $target } | Out-Null
            try {
                $settled = Wait-PlayerState $connection {
                    param($s) [Math]::Abs([double]$s.position - $target) -le $SeekToleranceSeconds
                } $SeekTimeoutMs "seek to $target seconds"
                $seekResults.Add([pscustomobject]@{ targetSeconds=$target; latencyMs=[int]$seekTimer.ElapsedMilliseconds; finalPosition=[double]$settled.State.position; passed=$true })
            }
            catch {
                $caseErrors.Add($_.Exception.Message)
                $seekResults.Add([pscustomobject]@{ targetSeconds=$target; latencyMs=[int]$seekTimer.ElapsedMilliseconds; finalPosition=$null; passed=$false })
            }
        }

        $diag = Invoke-MpcRequest $connection 'player.getDiagnostics'
        $caseResult.diagnostics = $diag
        if ($null -ne $case.expectedRenderer -and [string]$diag.renderer.name -ne [string]$case.expectedRenderer) {
            $caseErrors.Add("Renderer '$($diag.renderer.name)' does not match expected '$($case.expectedRenderer)'.")
        }
        if ($null -ne $case.decoderContains) {
            $decoder = [string]$diag.renderer.decoder
            if ($decoder.IndexOf([string]$case.decoderContains, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                $caseErrors.Add("Decoder '$decoder' does not contain '$($case.decoderContains)'.")
            }
        }
        if ($null -ne $case.maxDroppedFrames -and $null -ne $diag.renderer.framesDropped -and
                [int]$diag.renderer.framesDropped -gt [int]$case.maxDroppedFrames) {
            $caseErrors.Add("Dropped frames $($diag.renderer.framesDropped) exceed limit $($case.maxDroppedFrames).")
        }

        $caseResult.passed = ($caseErrors.Count -eq 0)
    }
    catch {
        $caseErrors.Add($_.Exception.Message)
    }
    finally {
        if ($null -ne $connection) {
            try { Invoke-MpcRequest $connection 'player.quit' @{} 2000 | Out-Null } catch {}
            Close-MpcPipe $connection
        }
        if ($null -ne $process) {
            try {
                if (-not $process.WaitForExit(5000)) { $process.Kill() }
            } catch {}
            $process.Dispose()
        }
    }
    $results.Add([pscustomobject]$caseResult)
}

$summary = [ordered]@{
    schemaVersion = 1
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    player = $playerFullPath
    manifest = $manifestFullPath
    passed = (@($results | Where-Object passed).Count -eq $results.Count)
    total = $results.Count
    passedCount = @($results | Where-Object passed).Count
    failedCount = @($results | Where-Object { -not $_.passed }).Count
    cases = $results
}
$outputFullPath = Resolve-RepoPath $OutputPath
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputFullPath) | Out-Null
$summary | ConvertTo-Json -Depth 20 | Set-Content $outputFullPath -Encoding UTF8
Write-Host "Playback results: $($summary.passedCount)/$($summary.total) passed -> $outputFullPath"
if (-not $summary.passed) { exit 1 }
