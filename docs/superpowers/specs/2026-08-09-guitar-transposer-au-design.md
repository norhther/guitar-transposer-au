# Guitar Transposer AUv3 — Design Spec

## Purpose

iPad AUv3 (Audio Unit v3) effect plugin that shifts a guitar's pitch up or
down by a constant interval, -12 to +12 semitones, in real time — used to
play a physically-tuned instrument as if it were in a different tuning
(e.g. play in standard tuning, hear Drop D) without retuning the guitar.
Comparable in purpose to Neural DSP's transposer feature, built as a
standalone plugin usable in any AUv3 host (GarageBand, AUM, Cubasis, etc).

## Non-goals (v1)

- No presets/tuning names, no preset save/recall
- No amp sim, no other effects — pitch shift only
- No App Store submission yet (personal sideload via Xcode/TestFlight)
- No standalone mic-monitor app — container app is a bare AUv3 host shell
- No pitch detection / monophonic note tracking — this is a broadband
  shifter, works on chords and single notes alike

## Distribution

Private GitHub repo `guitar-transposer-au` under `norhther`. Personal
sideload for now via Xcode → device / TestFlight internal testing.
Structured so bundle ID, privacy manifest, and App Store Connect setup can
be added later without restructuring the code.

## Platform Target

iOS 17+, iPad only. Swift 5.10+, Xcode 16+.

## Architecture

Xcode project, two targets:

- **`TransposerApp`** — bare SwiftUI container app. Required by Apple for
  any AUv3 to install; embeds the extension, shows the same control UI
  standalone (extension isn't loaded in isolation — app exists to satisfy
  the install requirement, not to be the primary use surface).
- **`TransposerExtension`** — the AUv3 audio unit itself, component type
  `aufx` (effect), subclass of `AUAudioUnit`.

### DSP Core

[Signalsmith Stretch](https://github.com/Signalsmith-Audio/signalsmith-stretch)
(MIT license), vendored as a header-only C++ dependency (git submodule or
copied into `Vendor/`). Chosen over SoundTouch/WSOLA because it's built
specifically for low-latency real-time pitch-shift/time-stretch and has
lower default latency with fewer artifacts on broadband/polyphonic
material (chords) — a better match for "state of the art, lowest latency"
than time-domain WSOLA approaches.

Wrapped in a small Objective-C++ bridge (`SignalsmithBridge.h/.mm`) since
the AUv3 render block is a C function pointer and Stretch's API is C++.
Bridge exposes: `configure(sampleRate, blockSize)`, `setSemitones(Float)`,
`process(inputBuffer, outputBuffer, frameCount)`.

### Audio Unit (`TransposerAudioUnit : AUAudioUnit`)

- Owns one `SignalsmithBridge` instance
- `internalRenderBlock` is real-time safe: **no allocation, no locks, no
  Obj-C messaging in the render path**. Bridge exposes a plain C++ process
  call taking raw buffer pointers.
- Parameter changes (semitones, latency mode) are written by the UI thread
  to atomics (`std::atomic<float>` in the bridge); render block reads them
  each block — standard AU lock-free parameter pattern.
- Latency-mode changes that require reconfiguring Stretch's internal block
  size happen **off the render thread** (dispatched to a serial queue),
  swapping in a freshly-configured bridge instance via atomic pointer swap
  — avoids allocating/reconfiguring inside the render callback.

### Parameters (`AUParameterTree`)

| Parameter | Type | Range | Notes |
|---|---|---|---|
| Semitones | Float, stepped | -12 ... +12, step 1 | Main control |
| Latency Mode | Indexed (enum) | Fast / Balanced / Quality | Changes Stretch block size; default Balanced |

`kAudioUnitProperty_Latency` is updated whenever Latency Mode changes, so
the host re-queries and adjusts its own buffering/PDC.

Latency targets: Fast <5ms lookahead (more artifacts), Balanced 10–20ms
(recommended default, matches typical quality AUv3 pitch shifters),
Quality >20ms (best pitch tracking quality, more lookahead).

### UI

Single SwiftUI view, shared by app and extension (extension provides it
via `createViewController()` / `AUViewController` hosting SwiftUI):

- Semitone stepper/knob, -12 to +12, current value + interval name label
  (e.g. "+2 (Whole tone up)")
- Latency Mode segmented control (Fast / Balanced / Quality)
- Bypass toggle
- Input/output level meters (basic peak meter, read from render block via
  a lock-free ring buffer or atomic peak-hold, polled by UI timer — meter
  data must not block or allocate in the render path either)

Bound to the `AUParameterTree` via `AUParameterObserverToken`, standard
AUv3 parameter-observation pattern — works identically whether hosted
standalone in the app or inside a DAW.

## Data Flow

```
Guitar → Audio Interface → Host DAW (GarageBand/AUM) → TransposerExtension.internalRenderBlock
  → SignalsmithBridge::process() → pitch-shifted buffer → back to host → Output
```

Parameter UI (app or host's plugin view) → AUParameterTree → atomics read
by render block. Latency Mode change → serial queue reconfigures bridge →
atomic swap → `kAudioUnitProperty_Latency` updated → host notified.

## Error Handling

- `internalRenderBlock` must never throw/crash regardless of input
  (silence, NaN/denormal guard on output, clamp buffer sizes)
- Bridge `configure()` failures (e.g. unsupported sample rate) fall back to
  a safe default block size rather than leaving the unit unconfigured
- AU validation (`auval`) failures are treated as build-blocking, not
  warnings

## Testing

- **`auval -v aufx <subtype> <manufacturer>`** — Apple's AU conformance
  validator, run after every DSP/parameter change; must pass clean before
  manual testing
- **Manual on-device**: load in GarageBand and AUM, guitar via audio
  interface, verify:
  - Pitch shifts correctly across full -12..+12 range (tune-match against
    a reference, e.g. play open string transposed +12, compare to actual
    octave-up fretted note)
  - Chords (polyphonic input) shift cleanly, no obvious phasiness/warble
  - No dropouts/glitches during Latency Mode switching mid-play
  - Latency feels acceptable for real-time playing at Balanced setting
- No automated DSP unit tests in v1 (per YAGNI decision) — revisit if bugs
  recur that manual testing keeps missing

## Repo Setup

- Private repo `norhther/guitar-transposer-au`
- Standard `.gitignore` for Xcode (`DerivedData/`, `*.xcuserstate`, etc)
- Signalsmith Stretch vendored under `Vendor/signalsmith-stretch/` (git
  submodule pointing at upstream, or a pinned copy if submodule friction
  isn't wanted — decide at implementation time)
