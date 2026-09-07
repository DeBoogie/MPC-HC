# Local testing guide

There is no hosted CI for this fork. Validation is performed locally so test depth is controlled by the developer rather than by GitHub Actions minutes.

## Static and build checks

Run the fast checks before every commit:

```powershell
powershell -ExecutionPolicy Bypass -File tools\verify-local.ps1
```

For code changes, also compile x64 Release Lite:

```powershell
powershell -ExecutionPolicy Bypass -File tools\verify-local.ps1 -Build
```

For security-sensitive C/C++ changes, run MSVC code analysis:

```powershell
powershell -ExecutionPolicy Bypass -File tools\verify-local.ps1 -Analyze
```

A full build that includes the internal LAV stack can be requested with `-Full` after the MSYS2/MinGW dependencies from `Compilation.md` are installed.

## Playback regression matrix

Before a release, exercise representative samples rather than only checking that the executable starts.

### Video and containers

- H.264/AVC in MP4 and MKV.
- HEVC Main/Main10 in MP4, MKV and MPEG-TS.
- AV1 8-bit and 10-bit.
- VVC when a known-good sample and decoder path are available.
- MPEG-2/DVD material for legacy compatibility.
- Variable-frame-rate material and files with discontinuous timestamps.
- A damaged/truncated file to check graceful failure.

### Hardware paths

On at least Intel, AMD and NVIDIA hardware where available:

- D3D11 native decode.
- D3D11 copy-back fallback.
- Software decode fallback.
- MPC Video Renderer presentation.
- Fullscreen transitions, seek, pause/resume and loop restart.
- Multi-monitor playback and DPI changes.

### HDR and color

- SDR BT.709.
- HDR10/PQ 10-bit output.
- HLG where available.
- HDR-to-SDR conversion on an SDR display.
- Correct limited/full range handling and subtitle composition over HDR video.

### Audio

- Stereo PCM.
- Multichannel PCM.
- AC-3/E-AC-3, DTS and TrueHD/DTS-HD bitstream paths where hardware is available.
- Shared and exclusive output modes.
- Audio-device hot-plug and default-device changes.
- Playback-rate changes with pitch correction.

### Subtitles

- SRT/SubRip.
- ASS/SSA with styled positioning.
- WebVTT.
- PGS/VobSub bitmap subtitles.
- RTL/complex-script text and font fallback.
- Subtitle delay adjustments while playing and seeking.

### Network and URL playback

- Direct HTTP/HTTPS media URL.
- HLS/DASH material supported by the current splitter stack.
- A current yt-dlp-supported URL.
- An invalid URL and an unsupported site.
- Network interruption/retry behavior.
- yt-dlp missing from disk, returning malformed JSON, or exiting with an error.

## Untrusted-input checks

Parser and process-launch changes should also be exercised with:

- Very long file paths and URLs.
- Empty and malformed playlists.
- Malformed subtitle files.
- Corrupt container headers.
- URLs containing escaped spaces, ampersands and Unicode.
- Large yt-dlp stdout/stderr responses.

Crashes, hangs and unbounded allocation are release blockers for these cases.
