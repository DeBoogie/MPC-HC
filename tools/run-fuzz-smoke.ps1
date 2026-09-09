[CmdletBinding()]
param(
    [string]$PlayerPath = 'bin\mpc-hc_x64\mpc-hc64.exe',
    [string]$CorpusDirectory = 'tests\fuzz\corpus',
    [string]$OutputDirectory = 'build\fuzz-results',
    [int]$Iterations = 100,
    [int]$Seed = 1337,
    [int]$TimeoutMs = 8000,
    [int]$MaxCaseBytes = 1048576,
    [switch]$GenerateOnly,
    [switch]$AddressSanitizer
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
function Resolve-RepoPath([string]$Path) {
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

function Connect-MpcPipe([int]$ProcessId, [int]$Timeout) {
    $pipe=[IO.Pipes.NamedPipeClientStream]::new('.',"MPC-HC-json-$ProcessId",[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::None)
    try {
        $pipe.Connect($Timeout)
        $utf8=[Text.UTF8Encoding]::new($false)
        $c=[pscustomobject]@{Pipe=$pipe;Writer=[IO.StreamWriter]::new($pipe,$utf8,4096,$true);Reader=[IO.StreamReader]::new($pipe,$utf8,$false,4096,$true);NextId=1}
        $c.Writer.AutoFlush=$true
        return $c
    } catch { $pipe.Dispose(); throw }
}
function Close-MpcPipe($c) { if($null-ne$c){$c.Writer.Dispose();$c.Reader.Dispose();$c.Pipe.Dispose()} }
function Invoke-MpcRequest($c,[string]$Method,[hashtable]$Params=@{},[int]$Timeout=8000) {
    $id=$c.NextId;$c.NextId++
    $c.Writer.WriteLine(([ordered]@{id=$id;method=$Method;params=$Params}|ConvertTo-Json -Depth 10 -Compress))
    $task=$c.Reader.ReadLineAsync()
    if(-not $task.Wait($Timeout)){throw "Timeout during $Method"}
    if($null-eq$task.Result){throw "Pipe closed during $Method"}
    $response=$task.Result|ConvertFrom-Json
    if($null-ne$response.error){throw "$Method failed ($($response.error.code)): $($response.error.message)"}
    return $response.result
}

function Mutate-Bytes([byte[]]$InputBytes,[Random]$Random,[int]$Limit) {
    $data=New-Object System.Collections.Generic.List[byte]
    $data.AddRange($InputBytes)
    if($data.Count -eq 0){$data.Add(0)}
    $operations=1+$Random.Next(1,8)
    for($op=0;$op-lt$operations;$op++){
        switch($Random.Next(0,7)){
            0 { # flip random bits
                $count=1+$Random.Next(1,[Math]::Min(32,[Math]::Max(2,$data.Count)))
                for($i=0;$i-lt$count;$i++){if($data.Count){$idx=$Random.Next($data.Count);$data[$idx]=$data[$idx]-bxor(1-shl$Random.Next(0,8))}}
            }
            1 { # overwrite range with random bytes
                if($data.Count){$start=$Random.Next($data.Count);$count=[Math]::Min(1+$Random.Next(1,128),$data.Count-$start);for($i=0;$i-lt$count;$i++){$data[$start+$i]=[byte]$Random.Next(0,256)}}
            }
            2 { # insert bytes
                if($data.Count-lt$Limit){$start=$Random.Next(0,$data.Count+1);$count=[Math]::Min(1+$Random.Next(1,256),$Limit-$data.Count);$bytes=New-Object byte[] $count;$Random.NextBytes($bytes);$data.InsertRange($start,$bytes)}
            }
            3 { # delete bytes
                if($data.Count-gt1){$start=$Random.Next($data.Count);$count=[Math]::Min(1+$Random.Next(1,128),$data.Count-$start);$data.RemoveRange($start,$count)}
            }
            4 { # truncate
                if($data.Count-gt1){$newLength=$Random.Next(0,$data.Count);if($newLength-lt$data.Count){$data.RemoveRange($newLength,$data.Count-$newLength)}}
            }
            5 { # duplicate a chunk
                if($data.Count-gt0-and$data.Count-lt$Limit){$start=$Random.Next($data.Count);$count=[Math]::Min(1+$Random.Next(1,128),$data.Count-$start);$room=$Limit-$data.Count;$count=[Math]::Min($count,$room);if($count-gt0){$chunk=$data.GetRange($start,$count).ToArray();$data.InsertRange($Random.Next(0,$data.Count+1),$chunk)}}
            }
            6 { # common parser edge bytes
                $edges=[byte[]](0,10,13,27,34,39,47,58,60,62,92,127,128,255)
                if($data.Count){$data[$Random.Next($data.Count)]=$edges[$Random.Next($edges.Length)]}
            }
        }
    }
    if($data.Count-gt$Limit){$data.RemoveRange($Limit,$data.Count-$Limit)}
    return ,$data.ToArray()
}

if($Iterations-lt1-or$Iterations-gt100000){throw 'Iterations must be between 1 and 100000.'}
if($MaxCaseBytes-lt1-or$MaxCaseBytes-gt67108864){throw 'MaxCaseBytes must be between 1 and 64 MiB.'}
$corpus=Resolve-RepoPath $CorpusDirectory
if(-not(Test-Path $corpus -PathType Container)){throw "Corpus directory not found: $corpus"}
$seeds=@(Get-ChildItem $corpus -File)
if($seeds.Count-eq0){throw 'Fuzz corpus is empty.'}
$out=Resolve-RepoPath $OutputDirectory
$casesDir=Join-Path $out 'cases';$findingsDir=Join-Path $out 'findings';$logsDir=Join-Path $out 'logs'
foreach($d in @($casesDir,$findingsDir,$logsDir)){New-Item -ItemType Directory -Force -Path $d|Out-Null}
$random=[Random]::new($Seed)
$generated=New-Object System.Collections.Generic.List[object]
for($i=0;$i-lt$Iterations;$i++){
    $seedFile=$seeds[$random.Next($seeds.Count)]
    $input=[IO.File]::ReadAllBytes($seedFile.FullName)
    $bytes=Mutate-Bytes $input $random $MaxCaseBytes
    $name=('case-{0:D6}{1}'-f$i,$seedFile.Extension)
    $path=Join-Path $casesDir $name
    [IO.File]::WriteAllBytes($path,$bytes)
    $generated.Add([pscustomobject]@{iteration=$i;seed=$seedFile.Name;path=$path;bytes=$bytes.Length})
}
if($GenerateOnly){
    $manifest=[ordered]@{schemaVersion=1;seed=$Seed;iterations=$Iterations;generatedUtc=[DateTime]::UtcNow.ToString('o');cases=$generated}
    $manifest|ConvertTo-Json -Depth 8|Set-Content (Join-Path $out 'generated-cases.json') -Encoding UTF8
    Write-Host "Generated $Iterations deterministic fuzz cases -> $casesDir"
    exit 0
}
$player=Resolve-RepoPath $PlayerPath
if(-not(Test-Path $player -PathType Leaf)){throw "MPC-HC executable not found: $player"}
$findings=New-Object System.Collections.Generic.List[object]
$originalAsan=$env:ASAN_SAVE_DUMPS
try {
    foreach($case in $generated){
        $proc=$null;$conn=$null
        $stderr=Join-Path $logsDir ("$($case.iteration)-stderr.txt")
        $stdout=Join-Path $logsDir ("$($case.iteration)-stdout.txt")
        if($AddressSanitizer){$env:ASAN_SAVE_DUMPS=Join-Path $findingsDir ("asan-$($case.iteration).dmp")}
        $kind=$null;$detail=$null
        try {
            $proc=Start-Process -FilePath $player -ArgumentList @('/new','/minimized','/nofocus') -PassThru -RedirectStandardError $stderr -RedirectStandardOutput $stdout
            $conn=Connect-MpcPipe $proc.Id $TimeoutMs
            Invoke-MpcRequest $conn 'player.open' @{path=$case.path} $TimeoutMs|Out-Null
            Invoke-MpcRequest $conn 'player.getState' @{} $TimeoutMs|Out-Null
            if($proc.HasExited){$kind='unexpected-exit';$detail="exit code $($proc.ExitCode)"}
        }
        catch {
            if($null-ne$proc-and$proc.HasExited){$kind='unexpected-exit';$detail="exit code $($proc.ExitCode): $($_.Exception.Message)"}
            else{$kind='unresponsive';$detail=$_.Exception.Message}
        }
        finally {
            if($null-ne$conn){try{Invoke-MpcRequest $conn 'player.quit' @{} 1500|Out-Null}catch{};Close-MpcPipe $conn}
            if($null-ne$proc){try{if(-not$proc.WaitForExit(3000)){$proc.Kill()}}catch{};$proc.Dispose()}
        }
        $asanText=''
        if(Test-Path $stderr){$asanText=Get-Content $stderr -Raw -ErrorAction SilentlyContinue}
        if($asanText -match 'AddressSanitizer'){$kind='address-sanitizer';$detail=($asanText -split "`r?`n"|Select-Object -First 8)-join"`n"}
        if($kind){
            $dest=Join-Path $findingsDir ([IO.Path]::GetFileName($case.path));Copy-Item $case.path $dest -Force
            $findings.Add([pscustomobject]@{iteration=$case.iteration;kind=$kind;detail=$detail;reproducer=$dest;seed=$case.seed})
        } else {
            Remove-Item $case.path -Force -ErrorAction SilentlyContinue
            Remove-Item $stderr,$stdout -Force -ErrorAction SilentlyContinue
        }
    }
}
finally{$env:ASAN_SAVE_DUMPS=$originalAsan}
$summary=[ordered]@{schemaVersion=1;generatedUtc=[DateTime]::UtcNow.ToString('o');seed=$Seed;iterations=$Iterations;findings=$findings.Count;items=$findings}
$summary|ConvertTo-Json -Depth 10|Set-Content (Join-Path $out 'fuzz-summary.json') -Encoding UTF8
Write-Host "Fuzz smoke complete: $Iterations cases, $($findings.Count) finding(s) -> $out"
if($findings.Count){exit 1}
