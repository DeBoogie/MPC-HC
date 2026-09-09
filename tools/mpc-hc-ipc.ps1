[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [int]$ProcessId,

    [Parameter(Mandatory = $true)]
    [string]$Method,

    [string]$ParamsJson = '{}',
    [int]$TimeoutMs = 10000
)

$ErrorActionPreference = 'Stop'
$pipeName = "MPC-HC-json-$ProcessId"
$params = $ParamsJson | ConvertFrom-Json
$request = [ordered]@{
    id = 1
    method = $Method
    params = $params
}
$json = $request | ConvertTo-Json -Depth 10 -Compress

$pipe = New-Object System.IO.Pipes.NamedPipeClientStream(
    '.',
    $pipeName,
    [System.IO.Pipes.PipeDirection]::InOut,
    [System.IO.Pipes.PipeOptions]::None)
try {
    $pipe.Connect($TimeoutMs)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $writer = New-Object System.IO.StreamWriter($pipe, $utf8, 4096, $true)
    $reader = New-Object System.IO.StreamReader($pipe, $utf8, $false, 4096, $true)
    try {
        $writer.AutoFlush = $true
        $writer.WriteLine($json)
        $task = $reader.ReadLineAsync()
        if (-not $task.Wait($TimeoutMs)) {
            throw "Timed out waiting for $pipeName."
        }
        if ($null -eq $task.Result) {
            throw 'MPC-HC closed the IPC connection without a response.'
        }
        $task.Result | ConvertFrom-Json
    }
    finally {
        $writer.Dispose()
        $reader.Dispose()
    }
}
finally {
    $pipe.Dispose()
}
