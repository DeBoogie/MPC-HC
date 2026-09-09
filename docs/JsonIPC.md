# JSON IPC

MPC-HC exposes a structured local automation API in addition to the legacy `WM_COPYDATA` API. The legacy API remains supported for compatibility.

## Transport

Each running process creates a byte-mode Windows named pipe:

```text
\\.\pipe\MPC-HC-json-<process-id>
```

The pipe rejects remote clients and its DACL grants access only to the Windows account that launched MPC-HC. This prevents another local account from controlling the player through the endpoint.

Requests and responses are UTF-8 JSON objects separated by a single newline. Individual requests are limited to 64 KiB. The current protocol version is `1`.

A bundled PowerShell client can be used for manual checks:

```powershell
powershell -ExecutionPolicy Bypass -File tools\mpc-hc-ipc.ps1 `
  -ProcessId 1234 `
  -Method player.getState
```

## Methods

### `player.getState`

Returns playback state (including `buffering`), absolute position and duration in seconds, playback rate, volume, mute state, current audio/subtitle track indices, and current file.

```json
{"id":1,"method":"player.getState","params":{}}
```

### `player.getDiagnostics`

Returns the state fields plus the configured video renderer and any `IQualProp` counters currently exposed by the renderer: active LAV decoder/hardware device plus frames drawn, frames dropped, jitter, and average sync offset. Missing renderer counters are omitted rather than fabricated.

```json
{"id":1,"method":"player.getDiagnostics","params":{}}
```

### Playback commands

```json
{"id":1,"method":"player.play","params":{}}
{"id":1,"method":"player.pause","params":{}}
{"id":1,"method":"player.stop","params":{}}
{"id":1,"method":"player.quit","params":{}}
{"id":1,"method":"player.seek","params":{"position":120.5}}
{"id":1,"method":"player.setRate","params":{"rate":1.25}}
{"id":1,"method":"player.setVolume","params":{"volume":75}}
{"id":1,"method":"player.setMute","params":{"muted":true}}
{"id":1,"method":"player.setAudioTrack","params":{"index":1}}
{"id":1,"method":"player.setSubtitleTrack","params":{"index":0}}
{"id":1,"method":"player.open","params":{"path":"C:\\Media\\sample.mkv"}}
```

Seek positions are bounded to a representable range and clamped to the loaded media duration. Playback rate is limited to `0.05..16.0`, volume to `0..100`, paths to 32767 UTF-16 code units, and embedded NUL characters are rejected.

## Response format

Every successful result includes `apiVersion: 1`. Successful commands return:

```json
{"id":1,"result":{"apiVersion":1,"ok":true}}
```

Errors are structured and use JSON-RPC-style numeric codes:

```json
{"id":1,"error":{"code":-32602,"message":"Volume must be between 0 and 100"}}
```

The API is intentionally marshalled onto the main window thread. The pipe worker performs transport and parsing only; it does not call DirectShow, renderer, playlist, or MFC UI objects directly.

## Internal layering

`JsonIpcServer` is only a transport/parser/serializer. Parsed requests are executed by the shared `CPlayerControlService` on the main UI thread. The same service also backs built-in web status, position and volume paths, which keeps validation/state semantics consistent across automation surfaces.
