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
- Built-in controls-page status polling through `/status.json`.
- Media/window titles containing quotes, backslashes, ampersands, angle brackets and non-ASCII text.
- Dynamic title/status text must render literally rather than becoming HTML markup.
- File-browser directory/file names and displayed paths containing ampersands or other HTML-significant text must render literally.
- Custom web pages/resources with empty, truncated, unreadable, or oversized files must fail cleanly without negative/narrowed buffer lengths or partial response bodies.
- Gzip responses for small/incompressible and compressible bodies must either use a complete valid gzip stream or fall back to the original uncompressed body.
- Client-supplied Cookie headers must not be reflected back as Set-Cookie response headers.
- The legacy `/status.html` endpoint remains reachable for third-party compatibility.
- Legacy `/status.html` fields containing quotes, backslashes, control characters, or Unicode remain syntactically escaped inside the `OnStatus(...)` envelope.

### Web server CGI

- CGI interpreter and script paths containing spaces and Unicode.
- Non-ASCII query strings and HTTP header values reaching the CGI environment intact.
- Request bodies larger than a single pipe write/read chunk.
- A CGI process that exits normally and one that exceeds the 30-second watchdog timeout.
- Repeated CGI requests while other player operations are active, checking for leaked process, thread, or pipe handles.

### Web server exposure

- A fresh profile with the web server enabled should listen only on `127.0.0.1`.
- Existing profiles with "Listen on localhost only" disabled should remain reachable from the LAN.
- Toggling "Listen on localhost only" should restart the listener and change its bind address.
- Localhost-only mode should reject connections through non-loopback interface addresses.

## Untrusted-input checks

Parser and process-launch changes should also be exercised with:

- Web-root requests containing `../`, `..\`, `%2e%2e`, mixed separators, and sibling-directory prefixes.
- A configured web default-index value containing traversal components; it must not escape the web root.
- Normal nested static files and configured directory-index files after the traversal checks are enabled.

- Very long file paths and URLs.
- Empty and malformed playlists.
- Malformed subtitle files.
- Corrupt container headers.
- URLs containing escaped spaces, ampersands and Unicode.
- Large yt-dlp stdout/stderr responses.
- Malformed HTTP request lines and header lines without required delimiters.
- Negative, non-decimal, duplicate, overflowing, and over-limit `Content-Length` values.
- Unsupported `Transfer-Encoding` request framing.
- Header terminators split across multiple socket receives.
- POST bodies that arrive in multiple receives or include bytes beyond the declared content length.

Crashes, hangs and unbounded allocation are release blockers for these cases.
