# Modernization policy

This fork keeps the MPC-HC model: a fast Windows media player with strong playback controls and broad format support, without growing into a media platform.

## Baseline

- The archived 2018 tree is preserved on the `legacy-2018` branch.
- `develop` was brought forward to the actively maintained MPC-HC code line before fork-specific modernization work started.
- Windows 10 is the minimum supported operating system for new builds.
- Visual Studio 2022 with the v143 toolset and a current Windows 10/11 SDK is the supported compiler setup.
- x64 is the primary build. Win32 remains in the solution only as a compatibility build until there is a reason to remove it.

## Playback architecture

Prefer maintained components over duplicating codec and renderer work inside the player:

- LAV Filters remain the internal splitter/decoder stack.
- MPC Video Renderer is the preferred modern renderer when supported.
- D3D11 decode/presentation paths are preferred on modern hardware.
- Legacy EVR/D3D9/DirectShow combinations remain available as compatibility fallbacks until they can be removed based on real hardware testing.
- SaneAR/MPC Audio Renderer behavior such as endpoint selection, exclusive output and bitstreaming should be preserved.

## Features to keep focused

High-value player features are in scope:

- Local files, discs, playlists and URL playback.
- H.264, HEVC, AV1, VVC and current audio formats through maintained decoder dependencies.
- HDR/10-bit playback and HDR-to-SDR handling through the renderer.
- Subtitle search, libass/WebVTT support, timing controls and complex-script rendering.
- Resume history, bookmarks, seekbar preview, A-B repeat and folder navigation.
- Customizable keyboard/mouse controls.
- Optional yt-dlp integration for supported web URLs.
- Portable configuration and normal Windows integration.

The following are deliberately out of scope unless a concrete use case changes that decision:

- Accounts, cloud sync, advertising or telemetry.
- A media-store or streaming-service catalog UI.
- An embedded browser.
- A plugin marketplace or skin ecosystem.
- A built-in transcoding/editing suite.
- A cross-platform UI rewrite.

## Security and maintenance

Media, playlists, subtitles and URLs are untrusted input. Changes in parsers, URL handling, external-process launch code and binary metadata readers deserve extra review.

Current hardening includes:

- `/GS` buffer security checks.
- SDL checks for first-party C/C++ builds.
- Control Flow Guard.
- DEP and ASLR.
- High-entropy VA and CET compatibility on x64.
- Explicit Windows 10 API targeting.
- Tighter yt-dlp pipe/handle lifetime and allocation handling.

Dependency updates should be small, reviewable changes. Update LAV Filters, MediaInfo, libass and renderer components independently where possible instead of vendoring new codec implementations into the player.

## Validation

This fork intentionally does not use GitHub Actions. Run local checks with:

```powershell
powershell -ExecutionPolicy Bypass -File tools\verify-local.ps1
```

Compile the x64 Release Lite target as part of the same check with:

```powershell
powershell -ExecutionPolicy Bypass -File tools\verify-local.ps1 -Build
```

Add `/Analyze` through the script with:

```powershell
powershell -ExecutionPolicy Bypass -File tools\verify-local.ps1 -Analyze
```

Use `-Full` when the local MSYS2/LAV build dependencies are installed and a full internal-codec build is required.

### Deterministic build inputs

External runtime binaries used by packages must be declared in `dependencies\manifest.json` with a source URL, SHA-256 digest, archive entry, destination, and expected file version. Use `tools\bootstrap-dependencies.ps1` rather than manually copying renderer binaries into `distrib`.

`tools\check-build-env.ps1` is the canonical prerequisite diagnostic and `tools\release.ps1` is the canonical local release entry point. Release output includes SHA-256 artifact metadata so a build can be tied back to its exact source commit and dependency manifest without requiring hosted CI.

## Player control architecture

New control surfaces must not add transport-specific playback logic to `CMainFrame`. `CPlayerControlService` is the transport-independent command/state boundary for remote control, test automation and web status/control paths:

```text
Named-pipe JSON ─┐
                 ├── CPlayerControlService ── CMainFrame / DirectShow
Built-in Web UI ─┘
```

The service owns validation and canonical state/diagnostic collection. Transport adapters parse their wire format and marshal requests to the player UI thread; they do not call DirectShow graph objects or mutate toolbar/player state directly from worker threads. The legacy WM_COPYDATA API remains supported separately for compatibility and can be migrated incrementally without changing its wire contract.

Cross-thread synchronous callers use the refcounted `WM_PLAYER_CONTROL_REQUEST` dispatch. The request object is heap-owned by caller and UI references independently, so a timeout cannot leave a queued UI message pointing at stack memory.

### Web process execution boundary

The built-in web remote may be exposed to a LAN, but configured CGI handlers are a separate process-execution capability. CGI is restricted to loopback clients by default even when the HTTP listener accepts LAN connections. `WebServerAllowCGIOverNetwork` is an explicit advanced opt-in for legacy deployments that require remote CGI. A denied mapped-script request is handled as HTTP 403 rather than being served as a static file.

### Network state and reconnect

LAV remains responsible for HTTP/HLS/DASH transport. MPC-HC adds a small player-level state machine around that transport so UI/automation can distinguish `connecting`, `buffering`, `retry-wait`, `reconnecting`, `ready`, and `failed`. A loaded network source that aborts uses the existing reopen path for bounded retries, preserving playback position and selected tracks instead of implementing a second network stack. The default policy is two retries with a 1500 ms base delay; both count and delay are advanced settings. Pending retries are tied to the current playlist URL and cancel themselves if the user changes media.
