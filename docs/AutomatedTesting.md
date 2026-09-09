# Automated playback and fuzz testing

The manual matrix in `Testing.md` remains the release coverage specification. The tools in this document make its repeatable portions machine-executable.

## Playback regression runner

`tools\run-playback-tests.ps1` launches a fresh MPC-HC process for every case and controls it through the same-user JSON IPC endpoint. It records startup/media-ready/first-frame timing, seek latency, final renderer/decoder/hardware-device diagnostics, frame drops, jitter, and synchronization offset when the active renderer exposes those values.

Create a local manifest from `tests\playback\manifest.example.json` and point each entry at a known-good sample. Paths in a manifest are resolved relative to that manifest.

```powershell
Copy-Item tests\playback\manifest.example.json tests\playback\manifest.json
# Edit local media paths, then:
powershell -ExecutionPolicy Bypass -File tools\run-playback-tests.ps1 `
  -PlayerPath 'bin\mpc-hc_x64\mpc-hc64.exe' `
  -ManifestPath 'tests\playback\manifest.json'
```

The result is written as JSON under `build\test-results` by default. A non-zero exit code means at least one case failed its thresholds.

Manifest-level assertions currently include:

- Minimum duration.
- Expected renderer name.
- Active decoder substring.
- Maximum dropped frames.
- Expected player-level network state through optional `expectedNetworkState`.
- One or more absolute seek positions with a configurable settle tolerance.

Use `-ValidateManifestOnly` when editing a manifest without a built player.

## AddressSanitizer build

MSVC AddressSanitizer can be enabled for the normal x86/x64 build with the `ASAN` switch:

```powershell
build.bat Build x64 MPCHC Release Lite ASAN
```

or through the modernization verifier:

```powershell
powershell -ExecutionPolicy Bypass -File tools\verify-local.ps1 -Sanitize
```

The build keeps the normal Release optimization settings and adds `/fsanitize=address` to C/C++ compilation. Microsoft documents AddressSanitizer as compatible with optimized `/O2 /GL` code. The switch is intentionally not enabled for release packages; it is a validation build.

## Mutation-based parser fuzz smoke

`tools\run-fuzz-smoke.ps1` is a deterministic black-box mutation runner. Seed files live under `tests\fuzz\corpus`. It preserves the seed extension so Windows/MPC-HC routes each mutated file to the same parser family, then launches an isolated MPC-HC process, opens the case through JSON IPC, verifies that the control endpoint remains responsive, and closes the process.

Generate cases without executing a player:

```powershell
powershell -ExecutionPolicy Bypass -File tools\run-fuzz-smoke.ps1 `
  -GenerateOnly -Iterations 100 -Seed 1337
```

Exercise an AddressSanitizer build:

```powershell
powershell -ExecutionPolicy Bypass -File tools\run-fuzz-smoke.ps1 `
  -PlayerPath 'bin\mpc-hc_x64 Lite\mpc-hc64.exe' `
  -Iterations 1000 -AddressSanitizer
```

Each mutation applies a bounded combination of bit flips, overwrites, insertion, deletion, truncation, chunk duplication, and parser-significant edge bytes. Input size is capped (1 MiB by default, 64 MiB hard maximum). Unexpected process exits, IPC non-responsiveness, and AddressSanitizer reports are copied to `build\fuzz-results\findings` with the exact reproducer. When `-AddressSanitizer` is used, the runner also sets `ASAN_SAVE_DUMPS` per case.

The black-box runner complements, rather than replaces, library-native fuzz targets in dependencies such as FFmpeg/libass. Its purpose is to exercise MPC-HC-specific routing, playlist/subtitle handling, graph creation, and glue code with the actual executable.

## Test corpus policy

Do not commit copyrighted feature films or large binary samples. Keep local samples small, legally redistributable, and purpose-built where possible. A useful local corpus should cover the matrix already listed in `Testing.md`: H.264/HEVC/AV1/VVC, VFR/discontinuous timestamps, HDR10/HLG, audio bitstreaming, text/bitmap subtitles, HLS/DASH, malformed/truncated files, and representative Intel/AMD/NVIDIA hardware paths.
