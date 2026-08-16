# Guitar Transposer

A real-time pitch shifter built as an iOS AUv3 audio unit, made mainly because I wanted to transpose a guitar signal on the fly without the usual latency/warble tradeoff you get from cheaper pitch-shift plugins.

It's not a toy demo — it's a usable AUv3 you can drop into GarageBand, Cubasis, AUM, or any other AU host on iOS and actually play through.

## Why this exists

I wanted to detune/transpose a guitar in real time while jamming, without reaching for a pedal or re-tuning. Most free pitch shifters either sound glassy/robotic when pushed more than a few semitones, or add so much latency they're unusable for live playing. So I built one around a DSP library that's actually designed for this.

## The DSP

Pitch shifting is powered by [Signalsmith Stretch](https://github.com/Signalsmith-Audio/signalsmith-stretch), the same phase-vocoder-based time/pitch library behind Signalsmith's own plugins. It's pulled in as a git submodule (along with `signalsmith-linear`) and wired into the audio unit through a small Objective-C++ bridge (`SignalsmithBridge.mm`) since the library itself is C++.

That gets you clean pitch shifting without the chipmunk/demon artifacts you get from naive resampling, plus a formant shift/compensation control so shifted notes don't sound like a different person singing them.

## Features

- Real-time semitone transposition, ±2 octaves
- Formant shift + formant compensation, so pitch and timbre can move independently
- Latency mode switch (trade responsiveness for quality depending on what you're doing)
- Advanced mode exposing the underlying Signalsmith Stretch parameters directly: block size, overlap, tonality limit — for people who want to tune the sound themselves
- Runs as an AUv3 app extension, so it works inside any AU host, plus a standalone host app for testing

## Project layout

```
TransposerApp/         standalone host app (mainly for testing/dev)
TransposerExtension/   the actual AUv3 audio unit + DSP bridge
Shared/                UI and parameter code shared between app and extension
Vendor/                signalsmith-stretch and signalsmith-linear (submodules)
```

## Building

```bash
git clone --recurse-submodules <this repo>
cd guitar-transposer-au
./regenerate.sh   # generates the .xcodeproj via XcodeGen
open GuitarTransposer.xcodeproj
```

Requires Xcode with iOS 17+ SDK. If you cloned without `--recurse-submodules`, run `git submodule update --init --recursive` before building — the extension won't compile without the DSP vendor code.

## Status

Working and installable on-device. Still iterating on parameter defaults and UI polish. Not on the App Store (yet) — build and sideload it yourself for now.

## License

Signalsmith Stretch and Signalsmith Linear are pulled in as submodules under their own licenses (see the [signalsmith-stretch](https://github.com/Signalsmith-Audio/signalsmith-stretch) and [linear](https://github.com/Signalsmith-Audio/linear) repos). Everything else in this repo is mine — check back for a license file if you want to reuse it.
