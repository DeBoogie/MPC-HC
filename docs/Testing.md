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


## Automated runners

Repeatable playback and malformed-input checks are available through `tools\run-playback-tests.ps1` and `tools\run-fuzz-smoke.ps1`. AddressSanitizer validation builds use the `ASAN` build switch or `tools\verify-local.ps1 -Sanitize`. See `AutomatedTesting.md` for the manifest format, metrics, fuzz bounds and reproducer handling.

## Playback regression matrix

Before a release, exercise representative samples rather than only checking that the executable starts.

### Video and containers

- H.264/AVC in MP4 and MKV.
- HEVC Main/Main10 in MP4, MKV and MPEG-TS.
- AV1 8-bit and 10-bit.
- VVC when a known-good sample and decoder path are available.
- MPEG-2/DVD material for legacy compatibility.
- DVD IFO handling: short reads/writes and malformed PGCI table counts, lengths, and offsets must fail or be ignored without accessing outside the loaded IFO buffer.
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

- OpenSubtitles movie-hash generation: reject files smaller than 128 KiB, require exact first/last 64 KiB probes, and verify the official `breakdance.avi` test vector (`8e245d9679d31e12`) when the sample is available.
- Subtitle provider file-info extraction must reject null current-file names and negative DirectShow reader lengths instead of converting them to huge unsigned sizes.
- Empty, truncated, malformed, and oversized (>4 MiB) `.nfo` sidecars must be ignored safely; normal sidecars should still populate IMDb IDs.
- Downloaded gzip/zlib/ZIP/RAR subtitle archives must reject entries over 32 MiB, total extracted output over 64 MiB, archives with more than 1024 entries, truncated/CRC-invalid ZIP data, and RAR callbacks that exceed the per-entry limit; Unicode temp paths must still work.
- SRT/SubRip.
- ASS/SSA with styled positioning.
- WebVTT.
- PGS/VobSub bitmap subtitles.
- RTL/complex-script text and font fallback.
- Subtitle delay adjustments while playing and seeking.

### Network and URL playback

- Direct HTTP/HTTPS media URL.
- HTTP authentication prompts: credential prefill-pack failures should fall back safely, unpack failures must return an error and clear partial username/domain/password output, and user cancellation must remain cancellation.
- HLS/DASH material supported by the current splitter stack.
- A current yt-dlp-supported URL.
- An invalid URL and an unsupported site.
- Network interruption/retry behavior.
- Subtitle-provider HTTP transfers: follow redirects only when requested, honor HTTPS/custom ports on uploads, trust actual read counts rather than advertised lengths, and reject responses larger than 64 MiB.
- yt-dlp missing from disk, returning malformed JSON, or exiting with an error.
- Built-in controls-page status polling through `/status.json`.
- Media/window titles containing quotes, backslashes, ampersands, angle brackets and non-ASCII text.
- Dynamic title/status text must render literally rather than becoming HTML markup.
- With web debug output enabled, request headers, method, path, and version containing HTML-significant characters must render literally rather than becoming markup.
- File-browser directory/file names and displayed paths containing ampersands or other HTML-significant text must render literally.
- Custom web pages/resources with empty, truncated, unreadable, or oversized files must fail cleanly without negative/narrowed buffer lengths or partial response bodies.
- Gzip responses for small/incompressible and compressible bodies must either use a complete valid gzip stream or fall back to the original uncompressed body.
- Client-supplied Cookie headers must not be reflected back as Set-Cookie response headers.
- The legacy `/status.html` endpoint remains reachable for third-party compatibility.
- Legacy `/status.html` fields containing quotes, backslashes, control characters, or Unicode remain syntactically escaped inside the `OnStatus(...)` envelope.

### Web server CGI

- CGI mappings remain usable from localhost by default.
- When the web server is exposed to the LAN, a non-loopback request for an extension configured as CGI must return HTTP 403 and must not fall through to static-file serving.
- `WebServerAllowCGIOverNetwork` is an explicit advanced opt-in; enabling it restores configured CGI execution for non-loopback clients.
- The ordinary LAN web remote and built-in static pages must continue working while remote CGI is disabled.

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
- State-changing web parameters must reject trailing garbage, numeric overflow, NaN/infinite/out-of-range percentages, unsupported WM_COMMAND IDs, malformed seek times, and malformed resource/DVB IDs.
- Web `redir` parameters must accept normal local paths such as `/controls.html` but reject CR/LF/control characters, backslashes, scheme-relative `//host` targets, non-local targets, and excessive length.

Crashes, hangs and unbounded allocation are release blockers for these cases.
