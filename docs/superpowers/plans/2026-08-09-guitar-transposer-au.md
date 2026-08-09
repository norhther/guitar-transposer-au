# Guitar Transposer AUv3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an iPad AUv3 effect plugin (`aufx`) that shifts guitar pitch -12..+12 semitones in real time, backed by Signalsmith Stretch, hosted in a bare SwiftUI container app.

**Architecture:** Two Xcode targets generated via XcodeGen (`TransposerApp`, `TransposerExtension`) sharing SwiftUI/parameter code in `Shared/`. DSP lives in an Objective-C++ bridge (`SignalsmithBridge`) around the vendored Signalsmith Stretch C++ library, called from the extension's `internalRenderBlock`. Parameter/UI communication uses the standard `AUParameterTree` pattern.

**Tech Stack:** Swift 5, SwiftUI, AudioToolbox/AVFoundation (`AUAudioUnit`), Objective-C++ (Signalsmith Stretch bridge), XcodeGen (project generation), git submodules (vendored DSP libs).

## Global Constraints

- Deployment target: iOS 17.0+, iPad only (`TARGETED_DEVICE_FAMILY = 2`)
- Swift 5 tools; C++17 for the DSP bridge (`CLANG_CXX_LANGUAGE_STANDARD = c++17`)
- Bundle IDs: app `com.norhther.guitartransposer`, extension `com.norhther.guitartransposer.extension`
- Audio Unit identity: type `aufx`, subtype `gtrx`, manufacturer `Nort`
- No allocation/locks/Obj-C messaging in the steady-state render path. The one documented exception: a latency-mode change reconfigures the DSP engine synchronously on the render thread on the single block where the mode actually changes (rare, user-initiated, not steady-state) — see Task 3 rationale. This is an intentional, bounded simplification for v1, not an oversight.
- No presets, no XCTest target, no App Store scaffolding in v1 — matches the approved spec (`docs/superpowers/specs/2026-08-09-guitar-transposer-au-design.md`). Testing gate per task is `xcodebuild build` (generic iOS SDK build, proves the code actually compiles against the real Signalsmith Stretch API) plus, for the final task, on-device/Simulator manual verification in a real AUv3 host.
- **Correction to the committed spec:** the spec's testing section mentions `auval`. `auval` is a macOS-only CLI that validates system-registered Audio Component `.component` bundles — it does not apply to iOS App Extension AUv3s (ours), which are validated by running the container app on a Simulator/device and loading the plugin in an actual AUv3 host (GarageBand, AUM, or Apple's bundled Simulator host). Task 8 reflects this; no other change to the approved design.

---

### Task 1: Toolchain, Vendored DSP Libraries, Project Scaffold

**Files:**
- Create: `project.yml`
- Create (git submodules): `Vendor/signalsmith-stretch/`, `Vendor/signalsmith-linear/`
- Create: `TransposerApp/Info.plist`
- Create: `TransposerApp/TransposerApp.swift`
- Create: `TransposerApp/ContentView.swift`
- Create: `TransposerExtension/Info.plist`

**Interfaces:**
- Produces: an Xcode project (`GuitarTransposer.xcodeproj`) with two targets (`TransposerApp`, `TransposerExtension`) that later tasks add source files to.

- [ ] **Step 1: Install XcodeGen**

```bash
brew install xcodegen
xcodegen --version
```

Expected: prints a version number.

- [ ] **Step 2: Vendor Signalsmith Stretch and its dependency as git submodules**

```bash
cd /Users/norhther/Downloads/guitar-transposer-au
git submodule add https://github.com/Signalsmith-Audio/signalsmith-stretch.git Vendor/signalsmith-stretch
git submodule add https://github.com/Signalsmith-Audio/linear.git Vendor/signalsmith-linear
git submodule update --init --recursive
ls Vendor/signalsmith-stretch/signalsmith-stretch.h Vendor/signalsmith-linear/stft.h
```

Expected: both files listed, exist.

- [ ] **Step 3: Write `project.yml`**

```yaml
name: GuitarTransposer
options:
  bundleIdPrefix: com.norhther.guitartransposer
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
configs:
  Debug: debug
  Release: release
settings:
  base:
    SWIFT_VERSION: "5.0"
    CLANG_CXX_LANGUAGE_STANDARD: "c++17"
    CLANG_CXX_LIBRARY: "libc++"
    TARGETED_DEVICE_FAMILY: "2"
    IPHONEOS_DEPLOYMENT_TARGET: "17.0"
targets:
  TransposerApp:
    type: application
    platform: iOS
    sources:
      - path: TransposerApp
      - path: Shared
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.norhther.guitartransposer
        INFOPLIST_FILE: TransposerApp/Info.plist
    dependencies:
      - target: TransposerExtension
        embed: true
  TransposerExtension:
    type: app-extension
    platform: iOS
    sources:
      - path: TransposerExtension
      - path: Shared
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.norhther.guitartransposer.extension
        INFOPLIST_FILE: TransposerExtension/Info.plist
        SWIFT_OBJC_BRIDGING_HEADER: TransposerExtension/TransposerExtension-Bridging-Header.h
        HEADER_SEARCH_PATHS:
          - "$(SRCROOT)/Vendor/signalsmith-stretch"
          - "$(SRCROOT)/Vendor/signalsmith-linear/.."
```

Note: `signalsmith-stretch.h` does `#include "signalsmith-linear/stft.h"`; the second search path (`Vendor/signalsmith-linear/..` = `Vendor/`) makes `Vendor/signalsmith-linear/stft.h` resolve under that literal name.

- [ ] **Step 4: Create placeholder app sources so the project has something to build**

`TransposerApp/TransposerApp.swift`:

```swift
import SwiftUI

@main
struct TransposerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

`TransposerApp/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Guitar Transposer")
            .padding()
    }
}
```

- [ ] **Step 5: Write `TransposerApp/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSRequiresIPhoneOS</key>
	<true/>
	<key>UILaunchScreen</key>
	<dict/>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationPortraitUpsideDown</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 6: Write a minimal `TransposerExtension/Info.plist` (real AudioComponents dict added in Task 5; placeholder here just to let the target build)**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>XPC!</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.AudioUnit-UI</string>
		<key>NSExtensionPrincipalClass</key>
		<string>$(PRODUCT_MODULE_NAME).TransposerAudioUnitFactory</string>
	</dict>
</dict>
</plist>
```

- [ ] **Step 7: Create the bridging header stub (populated in Task 3)**

`TransposerExtension/TransposerExtension-Bridging-Header.h`:

```objc
// Populated in Task 3 with the SignalsmithBridge import.
```

- [ ] **Step 8: Create a placeholder `TransposerAudioUnitFactory` so the extension target links (real implementation in Task 5)**

`TransposerExtension/TransposerAudioUnitFactory.swift`:

```swift
import CoreAudioKit

public class TransposerAudioUnitFactory: AUViewController, AUAudioUnitFactory {
    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        try AUAudioUnit(componentDescription: componentDescription)
    }
}
```

- [ ] **Step 9: Generate the Xcode project and build both targets**

```bash
cd /Users/norhther/Downloads/guitar-transposer-au
xcodegen generate
xcodebuild -project GuitarTransposer.xcodeproj -scheme TransposerApp -destination 'generic/platform=iOS' -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`. (`CODE_SIGNING_ALLOWED=NO` lets an unsigned/no-team checkout build for verification; real device install in Task 8 needs a signing team set in Xcode.)

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "chore: scaffold Xcode project via XcodeGen, vendor Signalsmith Stretch"
```

---

### Task 2: Shared Parameter Addresses and Interval Naming

**Files:**
- Create: `Shared/TransposerParameterAddresses.swift`
- Create: `Shared/IntervalName.swift`

**Interfaces:**
- Produces: `enum TransposerParameterAddress: AUParameterAddress { case semitones = 0, latencyMode = 1 }` consumed by Task 4 (`TransposerAudioUnit`) and Task 6 (`TransposerView`). Plain Swift (not Objective-C) — this file is shared by both targets, and only `TransposerExtension` has an Objective-C bridging header configured (Task 3), so an `NS_ENUM` here would be invisible to `TransposerApp`'s copy of `Shared/`. A plain Swift enum has no such dependency.

- [ ] **Step 1: Write the shared parameter address enum**

`Shared/TransposerParameterAddresses.swift`:

```swift
import AudioToolbox

enum TransposerParameterAddress: AUParameterAddress {
    case semitones = 0
    case latencyMode = 1
}
```

- [ ] **Step 2: Write the interval naming helper**

`Shared/IntervalName.swift`:

```swift
import Foundation

/// Maps a semitone offset (-12...12) to a human-readable interval name,
/// e.g. 0 -> "Unison", 7 -> "+7 (Perfect 5th up)", -12 -> "-12 (Octave down)".
func intervalName(forSemitones semitones: Int) -> String {
    let names = [
        "Unison", "Minor 2nd", "Major 2nd", "Minor 3rd", "Major 3rd",
        "Perfect 4th", "Tritone", "Perfect 5th", "Minor 6th", "Major 6th",
        "Minor 7th", "Major 7th", "Octave"
    ]
    let clamped = max(-12, min(12, semitones))
    if clamped == 0 { return "Unison" }
    let name = names[abs(clamped)]
    let direction = clamped > 0 ? "up" : "down"
    let sign = clamped > 0 ? "+" : ""
    return "\(sign)\(clamped) (\(name) \(direction))"
}
```

- [ ] **Step 3: Verify the helper's logic with a standalone script run (no XCTest target in this project — see Global Constraints)**

```bash
cd /Users/norhther/Downloads/guitar-transposer-au
cat > /tmp/interval_check.swift <<'EOF'
import Foundation
func intervalName(forSemitones semitones: Int) -> String {
    let names = [
        "Unison", "Minor 2nd", "Major 2nd", "Minor 3rd", "Major 3rd",
        "Perfect 4th", "Tritone", "Perfect 5th", "Minor 6th", "Major 6th",
        "Minor 7th", "Major 7th", "Octave"
    ]
    let clamped = max(-12, min(12, semitones))
    if clamped == 0 { return "Unison" }
    let name = names[abs(clamped)]
    let direction = clamped > 0 ? "up" : "down"
    let sign = clamped > 0 ? "+" : ""
    return "\(sign)\(clamped) (\(name) \(direction))"
}
assert(intervalName(forSemitones: 0) == "Unison")
assert(intervalName(forSemitones: 7) == "+7 (Perfect 5th up)")
assert(intervalName(forSemitones: -12) == "-12 (Octave down)")
assert(intervalName(forSemitones: 1) == "+1 (Minor 2nd up)")
print("OK")
EOF
swift /tmp/interval_check.swift
```

Expected: prints `OK` with no assertion failures.

- [ ] **Step 4: Commit**

```bash
git add Shared/
git commit -m "feat: add shared parameter addresses and interval naming helper"
```

---

### Task 3: Signalsmith Stretch Bridge (Objective-C++)

**Files:**
- Create: `TransposerExtension/DSP/SignalsmithBridge.h`
- Create: `TransposerExtension/DSP/SignalsmithBridge.mm`
- Modify: `TransposerExtension/TransposerExtension-Bridging-Header.h`

**Interfaces:**
- Produces: `SignalsmithBridge` Obj-C class — `-initWithSampleRate:channelCount:`, `-requestLatencyMode:`, `-appliedLatencySamples`, `-setSemitones:`, `-processInputs:outputs:frameCount:`, and `TransposerLatencyMode` enum (`Fast=0, Balanced=1, Quality=2`) — consumed by Task 4 (`TransposerAudioUnit`).

**Design note (documented simplification):** a latency-mode change is requested from any thread via `-requestLatencyMode:` (just an atomic store) and applied by the render thread itself at the top of the next `-processInputs:outputs:frameCount:` call, by calling `SignalsmithStretch::configure()` inline. `configure()` resizes internal `std::vector`s, so that one render call does a heap allocation — acceptable because mode changes are rare, user-initiated, and not steady-state; every other call is allocation-free. This avoids building a full lock-free object-swap/reclamation scheme for a personal-use v1.

- [ ] **Step 1: Write the bridge header**

`TransposerExtension/DSP/SignalsmithBridge.h`:

```objc
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TransposerLatencyMode) {
    TransposerLatencyModeFast = 0,
    TransposerLatencyModeBalanced = 1,
    TransposerLatencyModeQuality = 2
};

NS_ASSUME_NONNULL_BEGIN

@interface SignalsmithBridge : NSObject

- (instancetype)initWithSampleRate:(double)sampleRate
                       channelCount:(NSInteger)channelCount NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Thread-safe from any thread. Takes effect on the render thread at the start of its
/// next -processInputs:outputs:frameCount: call.
- (void)requestLatencyMode:(TransposerLatencyMode)mode;

/// Thread-safe from any thread. Total input+output latency, in samples, for the mode
/// currently applied on the render thread.
- (NSInteger)appliedLatencySamples;

/// Thread-safe from any thread.
- (void)setSemitones:(float)semitones;

/// Thread-safe from any thread. Peak absolute sample value (0...1 for normal signal
/// levels) observed on the most recent -processInputs:outputs:frameCount: call.
- (float)inputPeak;
- (float)outputPeak;

/// Render-thread only. Applies any pending latency-mode change, then processes
/// frameCount frames from inputs into outputs (both [channel][frame] laid out,
/// channelCount channels as given at init). inputs and outputs must not alias.
- (void)processInputs:(const float * const *)inputs
               outputs:(float * const *)outputs
            frameCount:(uint32_t)frameCount;

@end

NS_ASSUME_NONNULL_END
```

- [ ] **Step 2: Write the bridge implementation**

`TransposerExtension/DSP/SignalsmithBridge.mm`:

```objc
#import "SignalsmithBridge.h"
#import <atomic>
#import <algorithm>
#import <cmath>
#include "signalsmith-stretch.h"

static int TransposerBlockSamples(double sampleRate, TransposerLatencyMode mode) {
    double blockSeconds;
    switch (mode) {
        case TransposerLatencyModeFast:     blockSeconds = 0.008; break;
        case TransposerLatencyModeBalanced: blockSeconds = 0.016; break;
        case TransposerLatencyModeQuality:  blockSeconds = 0.032; break;
    }
    return std::max(64, static_cast<int>(sampleRate * blockSeconds));
}

@implementation SignalsmithBridge {
    signalsmith::stretch::SignalsmithStretch<float> _stretch;
    double _sampleRate;
    int _channelCount;
    std::atomic<int> _pendingLatencyMode;
    std::atomic<int> _appliedLatencyMode;
    std::atomic<long> _appliedLatencySamples;
    std::atomic<float> _semitones;
    std::atomic<float> _inputPeak;
    std::atomic<float> _outputPeak;
}

- (instancetype)initWithSampleRate:(double)sampleRate channelCount:(NSInteger)channelCount {
    self = [super init];
    if (self) {
        _sampleRate = sampleRate;
        _channelCount = static_cast<int>(channelCount);
        _semitones.store(0.0f, std::memory_order_relaxed);
        _pendingLatencyMode.store(TransposerLatencyModeBalanced, std::memory_order_relaxed);
        _appliedLatencyMode.store(-1, std::memory_order_relaxed);
        _appliedLatencySamples.store(0, std::memory_order_relaxed);
        _inputPeak.store(0.0f, std::memory_order_relaxed);
        _outputPeak.store(0.0f, std::memory_order_relaxed);
        [self applyLatencyMode:TransposerLatencyModeBalanced];
    }
    return self;
}

- (void)applyLatencyMode:(TransposerLatencyMode)mode {
    int blockSamples = TransposerBlockSamples(_sampleRate, mode);
    int intervalSamples = std::max(32, blockSamples / 3);
    _stretch.configure(_channelCount, blockSamples, intervalSamples);
    _appliedLatencyMode.store(mode, std::memory_order_relaxed);
    long total = static_cast<long>(_stretch.inputLatency()) + static_cast<long>(_stretch.outputLatency());
    _appliedLatencySamples.store(total, std::memory_order_relaxed);
}

- (void)requestLatencyMode:(TransposerLatencyMode)mode {
    _pendingLatencyMode.store(mode, std::memory_order_relaxed);
}

- (NSInteger)appliedLatencySamples {
    return static_cast<NSInteger>(_appliedLatencySamples.load(std::memory_order_relaxed));
}

- (void)setSemitones:(float)semitones {
    _semitones.store(semitones, std::memory_order_relaxed);
}

- (float)inputPeak {
    return _inputPeak.load(std::memory_order_relaxed);
}

- (float)outputPeak {
    return _outputPeak.load(std::memory_order_relaxed);
}

static float TransposerPeakAbs(const float *samples, uint32_t frameCount) {
    float peak = 0.0f;
    for (uint32_t i = 0; i < frameCount; i++) {
        peak = std::max(peak, std::fabs(samples[i]));
    }
    return peak;
}

- (void)processInputs:(const float * const *)inputs
               outputs:(float * const *)outputs
            frameCount:(uint32_t)frameCount {
    int pending = _pendingLatencyMode.load(std::memory_order_relaxed);
    if (pending != _appliedLatencyMode.load(std::memory_order_relaxed)) {
        [self applyLatencyMode:static_cast<TransposerLatencyMode>(pending)];
    }
    _inputPeak.store(TransposerPeakAbs(inputs[0], frameCount), std::memory_order_relaxed);
    _stretch.setTransposeSemitones(_semitones.load(std::memory_order_relaxed));
    _stretch.process(inputs, static_cast<int>(frameCount), outputs, static_cast<int>(frameCount));
    _outputPeak.store(TransposerPeakAbs(outputs[0], frameCount), std::memory_order_relaxed);
}

@end
```

- [ ] **Step 3: Import the bridge into the bridging header**

Replace the contents of `TransposerExtension/TransposerExtension-Bridging-Header.h`:

```objc
#import "DSP/SignalsmithBridge.h"
```

- [ ] **Step 4: Regenerate the project (new files) and build**

```bash
cd /Users/norhther/Downloads/guitar-transposer-au
xcodegen generate
xcodebuild -project GuitarTransposer.xcodeproj -scheme TransposerExtension -destination 'generic/platform=iOS' -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`. This is the real compile-time check that the bridge's calls (`configure`, `setTransposeSemitones`, `process`, `inputLatency`, `outputLatency`) match Signalsmith Stretch's actual API.

- [ ] **Step 5: Commit**

```bash
git add TransposerExtension/
git commit -m "feat: add Signalsmith Stretch Objective-C++ bridge"
```

---

### Task 4: TransposerAudioUnit (AUAudioUnit Subclass)

**Files:**
- Create: `TransposerExtension/TransposerAudioUnit.swift`

**Interfaces:**
- Consumes: `SignalsmithBridge` (Task 3), `TransposerParameterAddress` (Task 2).
- Produces: `TransposerAudioUnit : AUAudioUnit` with public `parameterTree: AUParameterTree` (semitones + latencyMode params) and `func currentPeaks() -> (input: Float, output: Float)`, consumed by Task 6 (`TransposerView` binds to the tree) and Task 7 (`TransposerViewController` polls `currentPeaks()`). Instantiated by Task 5's factory.

- [ ] **Step 1: Write `TransposerAudioUnit.swift`**

```swift
import AVFoundation
import AudioToolbox

public class TransposerAudioUnit: AUAudioUnit {
    private var bridge: SignalsmithBridge!
    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    private var _inputBusArray: AUAudioUnitBusArray!
    private var _outputBusArray: AUAudioUnitBusArray!

    private let semitonesParam: AUParameter
    private let latencyModeParam: AUParameter
    private let paramTree: AUParameterTree

    public override init(componentDescription: AudioComponentDescription,
                          options: AudioComponentInstantiationOptions = []) throws {
        semitonesParam = AUParameterTree.createParameter(
            withIdentifier: "semitones",
            name: "Semitones",
            address: TransposerParameterAddress.semitones.rawValue,
            min: -12, max: 12,
            unit: .indexed,
            unitName: nil,
            flags: [.flag_IsWritable, .flag_IsReadable],
            valueStrings: nil,
            dependentParameters: nil)
        semitonesParam.value = 0

        latencyModeParam = AUParameterTree.createParameter(
            withIdentifier: "latencyMode",
            name: "Latency Mode",
            address: TransposerParameterAddress.latencyMode.rawValue,
            min: 0, max: 2,
            unit: .indexed,
            unitName: nil,
            flags: [.flag_IsWritable, .flag_IsReadable],
            valueStrings: ["Fast", "Balanced", "Quality"],
            dependentParameters: nil)
        latencyModeParam.value = 1

        paramTree = AUParameterTree.createTree(withChildren: [semitonesParam, latencyModeParam])

        try super.init(componentDescription: componentDescription, options: options)

        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)
        _inputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        _outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])

        paramTree.implementorValueObserver = { [weak self] param, value in
            guard let self = self, let address = TransposerParameterAddress(rawValue: param.address) else { return }
            switch address {
            case .semitones:
                self.bridge?.setSemitones(Float(value))
            case .latencyMode:
                if let mode = TransposerLatencyMode(rawValue: Int(value)) {
                    self.bridge?.requestLatencyMode(mode)
                }
            }
        }
        paramTree.implementorValueProvider = { param in
            param.value
        }
    }

    public override var parameterTree: AUParameterTree? {
        get { paramTree }
        set { }
    }

    public override var inputBusses: AUAudioUnitBusArray { _inputBusArray }
    public override var outputBusses: AUAudioUnitBusArray { _outputBusArray }

    public override var latency: TimeInterval {
        guard let bridge = bridge, outputBus.format.sampleRate > 0 else { return 0 }
        return Double(bridge.appliedLatencySamples()) / outputBus.format.sampleRate
    }

    /// Thread-safe from any thread (backed by the bridge's atomics). Polled by the UI timer
    /// in TransposerViewController (Task 7) — never called from the render thread itself.
    public func currentPeaks() -> (input: Float, output: Float) {
        guard let bridge = bridge else { return (0, 0) }
        return (bridge.inputPeak(), bridge.outputPeak())
    }

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        let sampleRate = outputBus.format.sampleRate
        let channelCount = Int(outputBus.format.channelCount)
        bridge = SignalsmithBridge(sampleRate: sampleRate, channelCount: channelCount)
        bridge.setSemitones(Float(semitonesParam.value))
        if let mode = TransposerLatencyMode(rawValue: Int(latencyModeParam.value)) {
            bridge.requestLatencyMode(mode)
        }
    }

    public override func deallocateRenderResources() {
        bridge = nil
        super.deallocateRenderResources()
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        let bridge = self.bridge!
        return { actionFlags, timestamp, frameCount, outputBusNumber, outputData, realtimeEventListHead, pullInputBlock in
            guard let pullInputBlock = pullInputBlock else { return kAudioUnitErr_NoConnection }

            var inputFlags = AudioUnitRenderActionFlags()
            let inputData = UnsafeMutableAudioBufferListPointer(outputData)
            let status = pullInputBlock(&inputFlags, timestamp, frameCount, 0, outputData)
            if status != noErr { return status }

            let bufferListPointer = UnsafeMutableAudioBufferListPointer(outputData)
            let channelCount = bufferListPointer.count

            var inputPointers: [UnsafePointer<Float>?] = []
            var outputPointers: [UnsafeMutablePointer<Float>?] = []
            for i in 0..<channelCount {
                let buf = bufferListPointer[i]
                let floatPtr = buf.mData!.assumingMemoryBound(to: Float.self)
                inputPointers.append(UnsafePointer(floatPtr))
                outputPointers.append(floatPtr)
            }

            inputPointers.withUnsafeBufferPointer { inPtrs in
                outputPointers.withUnsafeBufferPointer { outPtrs in
                    inPtrs.baseAddress!.withMemoryRebound(to: UnsafePointer<Float>?.self, capacity: channelCount) { inRaw in
                        outPtrs.baseAddress!.withMemoryRebound(to: UnsafeMutablePointer<Float>?.self, capacity: channelCount) { outRaw in
                            bridge.processInputs(UnsafePointer(inRaw._pointer as! UnsafePointer<UnsafePointer<Float>?>),
                                                  outputs: outRaw._pointer as! UnsafeMutablePointer<UnsafeMutablePointer<Float>?>,
                                                  frameCount: frameCount)
                        }
                    }
                }
            }
            return noErr
        }
    }
}
```

- [ ] **Step 2: Fix the render block's pointer plumbing (the withMemoryRebound trick above is fragile — replace with a direct, correct implementation)**

Replace the `internalRenderBlock` implementation with this direct version, which builds real `[UnsafePointer<Float>?]` / `[UnsafeMutablePointer<Float>?]` arrays and passes their base addresses directly (this is the standard, correct AUv3 pattern — the prior step's `withMemoryRebound` chain was overcomplicated and is discarded):

```swift
    public override var internalRenderBlock: AUInternalRenderBlock {
        let bridge = self.bridge!
        return { actionFlags, timestamp, frameCount, outputBusNumber, outputData, realtimeEventListHead, pullInputBlock in
            guard let pullInputBlock = pullInputBlock else { return kAudioUnitErr_NoConnection }

            var inputFlags = AudioUnitRenderActionFlags()
            let status = pullInputBlock(&inputFlags, timestamp, frameCount, 0, outputData)
            if status != noErr { return status }

            let bufferList = UnsafeMutableAudioBufferListPointer(outputData)
            let channelCount = bufferList.count

            var channelPointers: [UnsafeMutablePointer<Float>] = []
            channelPointers.reserveCapacity(channelCount)
            for i in 0..<channelCount {
                channelPointers.append(bufferList[i].mData!.assumingMemoryBound(to: Float.self))
            }

            var inputPointers: [UnsafePointer<Float>?] = channelPointers.map { UnsafePointer($0) }
            var outputPointers: [UnsafeMutablePointer<Float>?] = channelPointers

            inputPointers.withUnsafeMutableBufferPointer { inBuf in
                outputPointers.withUnsafeMutableBufferPointer { outBuf in
                    bridge.processInputs(inBuf.baseAddress!, outputs: outBuf.baseAddress!, frameCount: frameCount)
                }
            }
            return noErr
        }
    }
```

(Delete the Step 1 version of `internalRenderBlock` entirely — this replaces it. Because `outputData`'s buffers already contain the pulled input samples after `pullInputBlock` and Signalsmith Stretch's `process()` requires distinct input/output buffers, allocate a small scratch input copy per channel here instead of aliasing — see Step 3.)

- [ ] **Step 3: Fix the input/output aliasing bug — copy input to scratch buffers before processing in place**

Signalsmith Stretch's README states input and output buffers "cannot be the same." Step 2's version passes the same underlying memory as both input and output. Replace it with this corrected version that keeps a persistent (allocated once, in `allocateRenderResources`, not per-render) scratch buffer:

Add these two properties to the class (near `bridge`):

```swift
    private var scratchInput: [[Float]] = []
    private var scratchInputPointers: [UnsafeMutablePointer<Float>] = []
```

In `allocateRenderResources()`, after creating `bridge`, add:

```swift
        let maxFrames = Int(maximumFramesToRender)
        scratchInput = Array(repeating: [Float](repeating: 0, count: maxFrames), count: channelCount)
```

In `deallocateRenderResources()`, add `scratchInput = []` before `super.deallocateRenderResources()`.

Replace the `internalRenderBlock` body from Step 2 with:

```swift
    public override var internalRenderBlock: AUInternalRenderBlock {
        let bridge = self.bridge!
        return { [weak self] actionFlags, timestamp, frameCount, outputBusNumber, outputData, realtimeEventListHead, pullInputBlock in
            guard let self = self, let pullInputBlock = pullInputBlock else { return kAudioUnitErr_NoConnection }

            var inputFlags = AudioUnitRenderActionFlags()
            let status = pullInputBlock(&inputFlags, timestamp, frameCount, 0, outputData)
            if status != noErr { return status }

            let bufferList = UnsafeMutableAudioBufferListPointer(outputData)
            let channelCount = bufferList.count
            let frames = Int(frameCount)

            var inputPointers: [UnsafePointer<Float>?] = []
            var outputPointers: [UnsafeMutablePointer<Float>?] = []
            inputPointers.reserveCapacity(channelCount)
            outputPointers.reserveCapacity(channelCount)

            for i in 0..<channelCount {
                let outPtr = bufferList[i].mData!.assumingMemoryBound(to: Float.self)
                self.scratchInput[i].withUnsafeMutableBufferPointer { scratch in
                    scratch.baseAddress!.update(from: outPtr, count: frames)
                }
                outputPointers.append(outPtr)
            }
            for i in 0..<channelCount {
                self.scratchInput[i].withUnsafeMutableBufferPointer { scratch in
                    inputPointers.append(UnsafePointer(scratch.baseAddress!))
                }
            }

            inputPointers.withUnsafeMutableBufferPointer { inBuf in
                outputPointers.withUnsafeMutableBufferPointer { outBuf in
                    bridge.processInputs(inBuf.baseAddress!, outputs: outBuf.baseAddress!, frameCount: frameCount)
                }
            }
            return noErr
        }
    }
```

Note: `scratchInput[i].withUnsafeMutableBufferPointer` closures used just to obtain stable pointers without triggering copy-on-write — since `scratchInput` is a `var` array of arrays captured by `self`, mutating `scratch.baseAddress!` directly (not the Swift array value) inside the closure keeps this allocation-free per call, satisfying the real-time constraint.

- [ ] **Step 4: Regenerate and build**

```bash
cd /Users/norhther/Downloads/guitar-transposer-au
xcodegen generate
xcodebuild -project GuitarTransposer.xcodeproj -scheme TransposerExtension -destination 'generic/platform=iOS' -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add TransposerExtension/
git commit -m "feat: implement TransposerAudioUnit render block and parameter tree"
```

---

### Task 5: Extension Factory, View Controller, and Real Info.plist

**Files:**
- Modify: `TransposerExtension/TransposerAudioUnitFactory.swift`
- Modify: `TransposerExtension/Info.plist`

**Interfaces:**
- Consumes: `TransposerAudioUnit` (Task 4).
- Produces: registered `aufx`/`gtrx`/`Nort` Audio Component that any AUv3 host can discover once the app is installed.

- [ ] **Step 1: Replace the placeholder factory**

`TransposerExtension/TransposerAudioUnitFactory.swift`:

```swift
import CoreAudioKit

public class TransposerAudioUnitFactory: AUViewController, AUAudioUnitFactory {
    private var audioUnit: TransposerAudioUnit?

    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let audioUnit = try TransposerAudioUnit(componentDescription: componentDescription, options: [])
        self.audioUnit = audioUnit
        return audioUnit
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        guard let audioUnit = audioUnit else { return }
        let hosting = TransposerViewController(audioUnit: audioUnit)
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }
}
```

(`TransposerViewController` is created in Task 7 — this file references it but won't compile until Task 7 exists; that's expected and fixed by Task 7's build step. Do not run the build step for this task in isolation.)

- [ ] **Step 2: Replace `TransposerExtension/Info.plist` with the real AudioComponents description**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>XPC!</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionAttributes</key>
		<dict>
			<key>AudioComponents</key>
			<array>
				<dict>
					<key>description</key>
					<string>Real-time guitar pitch transposer, -12 to +12 semitones</string>
					<key>manufacturer</key>
					<string>Nort</string>
					<key>name</key>
					<string>Norhther: Guitar Transposer</string>
					<key>subtype</key>
					<string>gtrx</string>
					<key>tags</key>
					<array>
						<string>Effects</string>
						<string>Pitch</string>
					</array>
					<key>type</key>
					<string>aufx</string>
					<key>version</key>
					<integer>1</integer>
					<key>sandboxSafe</key>
					<true/>
				</dict>
			</array>
		</dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.AudioUnit-UI</string>
		<key>NSExtensionPrincipalClass</key>
		<string>$(PRODUCT_MODULE_NAME).TransposerAudioUnitFactory</string>
	</dict>
</dict>
</plist>
```

- [ ] **Step 3: Commit (build deferred to Task 7, which supplies the missing `TransposerViewController`)**

```bash
git add TransposerExtension/
git commit -m "feat: wire AUv3 extension factory and AudioComponents Info.plist"
```

---

### Task 6: Shared SwiftUI Control View and Peak Meter

**Files:**
- Create: `Shared/PeakMeter.swift`
- Create: `Shared/TransposerView.swift`

**Interfaces:**
- Consumes: `intervalName(forSemitones:)` (Task 2), `AUParameterTree` shape from Task 4 (`semitones`, `latencyMode` identifiers).
- Produces: `PeakMeterStore` (an `ObservableObject` with `@Published var inputLevel: Float` / `outputLevel: Float`, plus a real-time-safe `func report(input: Float, output: Float)`) and `TransposerView(parameterTree: AUParameterTree, meter: PeakMeterStore)` consumed by Task 7.

- [ ] **Step 1: Write the peak meter store**

`Shared/PeakMeter.swift`:

```swift
import Foundation
import Combine

/// Holds the latest peak levels for UI display. `report(input:output:)` is called from a
/// UI-thread polling timer (Task 7), reading values written by the render thread via atomics —
/// not called from the render thread itself, so no real-time-safety constraints apply here.
final class PeakMeterStore: ObservableObject {
    @Published var inputLevel: Float = 0
    @Published var outputLevel: Float = 0

    func report(input: Float, output: Float) {
        inputLevel = input
        outputLevel = output
    }
}
```

- [ ] **Step 2: Write the shared control view**

`Shared/TransposerView.swift`:

```swift
import SwiftUI
import AudioToolbox

struct TransposerView: View {
    @ObservedObject var meter: PeakMeterStore
    let parameterTree: AUParameterTree

    @State private var semitones: Double = 0
    @State private var latencyModeIndex: Double = 1
    @State private var bypassed: Bool = false

    private var semitonesParam: AUParameter { parameterTree.parameter(withAddress: TransposerParameterAddress.semitones.rawValue)! }
    private var latencyModeParam: AUParameter { parameterTree.parameter(withAddress: TransposerParameterAddress.latencyMode.rawValue)! }

    var body: some View {
        VStack(spacing: 24) {
            Text(intervalName(forSemitones: Int(semitones)))
                .font(.title2).bold()

            Stepper(value: $semitones, in: -12...12, step: 1) {
                Text("Semitones: \(Int(semitones))")
            }
            .onChange(of: semitones) { newValue in
                semitonesParam.value = AUValue(newValue)
            }

            Picker("Latency Mode", selection: $latencyModeIndex) {
                Text("Fast").tag(0.0)
                Text("Balanced").tag(1.0)
                Text("Quality").tag(2.0)
            }
            .pickerStyle(.segmented)
            .onChange(of: latencyModeIndex) { newValue in
                latencyModeParam.value = AUValue(newValue)
            }

            Toggle("Bypass", isOn: $bypassed)

            HStack {
                MeterBar(label: "In", level: meter.inputLevel)
                MeterBar(label: "Out", level: meter.outputLevel)
            }
        }
        .padding()
        .onAppear {
            semitones = Double(semitonesParam.value)
            latencyModeIndex = Double(latencyModeParam.value)
        }
    }
}

private struct MeterBar: View {
    let label: String
    let level: Float

    var body: some View {
        VStack {
            Text(label).font(.caption)
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Rectangle().fill(Color.gray.opacity(0.2))
                    Rectangle()
                        .fill(Color.green)
                        .frame(height: geo.size.height * CGFloat(min(max(level, 0), 1)))
                }
            }
            .frame(width: 24, height: 80)
        }
    }
}
```

- [ ] **Step 3: Commit (this file compiles standalone against SwiftUI/AudioToolbox; full build verification happens in Task 7 once it's wired into a target's view controller)**

```bash
git add Shared/
git commit -m "feat: add shared SwiftUI control view and peak meter store"
```

---

### Task 7: Host View Controller and App Target Wiring

**Files:**
- Create: `Shared/TransposerViewController.swift`
- Modify: `TransposerApp/ContentView.swift`
- Modify: `TransposerApp/TransposerApp.swift`

**Interfaces:**
- Consumes: `TransposerView`, `PeakMeterStore` (Task 6), `TransposerAudioUnit` (Task 4).
- Produces: `TransposerViewController(audioUnit: TransposerAudioUnit) : UIViewController`, used by both `TransposerAudioUnitFactory` (Task 5, extension side) and `TransposerApp` (app side, standalone display).

- [ ] **Step 1: Write the shared UIKit host for the SwiftUI view**

`Shared/TransposerViewController.swift`:

```swift
import UIKit
import SwiftUI
import AudioToolbox

/// Hosts TransposerView in a UIViewController, for use both as the AUv3 extension's
/// view controller and inside the standalone app. Polls peak levels on a UI timer —
/// the render thread itself never touches this class.
final class TransposerViewController: UIViewController {
    private let audioUnit: TransposerAudioUnit
    private let meter = PeakMeterStore()
    private var timer: Timer?

    init(audioUnit: TransposerAudioUnit) {
        self.audioUnit = audioUnit
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let tree = audioUnit.parameterTree else { return }
        let hosting = UIHostingController(rootView: TransposerView(meter: meter, parameterTree: tree))
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let peaks = self.audioUnit.currentPeaks()
            self.meter.report(input: peaks.input, output: peaks.output)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        timer = nil
    }
}
```

- [ ] **Step 2: Wire the app target to instantiate the extension's Audio Unit in-process and show the same UI**

`TransposerApp/ContentView.swift`:

```swift
import SwiftUI
import AudioToolbox
import AVFoundation

struct ContentView: View {
    @State private var audioUnit: TransposerAudioUnit?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let audioUnit = audioUnit {
                TransposerHostView(audioUnit: audioUnit)
            } else if let error = loadError {
                Text("Failed to load audio unit: \(error)")
            } else {
                ProgressView("Loading...")
            }
        }
        .onAppear(perform: loadAudioUnit)
    }

    private func loadAudioUnit() {
        var description = AudioComponentDescription()
        description.componentType = kAudioUnitType_Effect
        description.componentSubType = FourCharCode("gtrx".fourCharCode)
        description.componentManufacturer = FourCharCode("Nort".fourCharCode)
        description.componentFlags = 0
        description.componentFlagsMask = 0

        AUAudioUnit.registerSubclass(TransposerAudioUnit.self, as: description, name: "Norhther: Guitar Transposer", version: 1)

        AVAudioUnit.instantiate(with: description, options: []) { avAudioUnit, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.loadError = error.localizedDescription
                    return
                }
                self.audioUnit = avAudioUnit?.auAudioUnit as? TransposerAudioUnit
            }
        }
    }
}

private extension String {
    var fourCharCode: UInt32 {
        var result: UInt32 = 0
        for scalar in unicodeScalars.prefix(4) {
            result = (result << 8) + scalar.value
        }
        return result
    }
}

private struct TransposerHostView: UIViewControllerRepresentable {
    let audioUnit: TransposerAudioUnit

    func makeUIViewController(context: Context) -> TransposerViewController {
        TransposerViewController(audioUnit: audioUnit)
    }

    func updateUIViewController(_ uiViewController: TransposerViewController, context: Context) {}
}
```

- [ ] **Step 3: Regenerate and build both targets**

```bash
cd /Users/norhther/Downloads/guitar-transposer-au
xcodegen generate
xcodebuild -project GuitarTransposer.xcodeproj -scheme TransposerExtension -destination 'generic/platform=iOS' -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
xcodebuild -project GuitarTransposer.xcodeproj -scheme TransposerApp -destination 'generic/platform=iOS' -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: wire host view controller, app-side standalone AU instantiation"
```

---

### Task 8: On-Device Validation (Manual — Non-CLI)

**Files:** none (verification task).

This task requires Xcode's GUI and a connected iPad — do this yourself; it can't be scripted from here.

- [ ] **Step 1: Set a signing team**

Open `GuitarTransposer.xcodeproj` in Xcode. For both `TransposerApp` and `TransposerExtension` targets: Signing & Capabilities tab → select your Apple ID team → let Xcode auto-manage provisioning.

- [ ] **Step 2: Run on Simulator first**

Select the `TransposerApp` scheme, an iPad Simulator destination, Run. Confirm the app launches, shows "Loading..." then the transposer UI (stepper, latency mode segmented control, bypass toggle, meters) without crashing or showing "Failed to load audio unit."

- [ ] **Step 3: Run on your iPad**

Connect your iPad, select it as the run destination, Run. Same check as Step 2, on-device.

- [ ] **Step 4: Load it in a real AUv3 host and verify with your guitar**

With `TransposerApp` installed on the iPad (running it once is enough — installing the app registers the extension system-wide), open GarageBand for iPad (or AUM): add an Audio Unit Extension effect on a guitar-input track, find "Norhther: Guitar Transposer" under Effects. Verify:
- Playing an open string with Semitones at +12 sounds an octave up vs. the same string fretted at the 12th fret
- Chords (strum a full chord) shift cleanly — no obvious warble/phasiness
- Switching Latency Mode (Fast/Balanced/Quality) mid-play doesn't crash or hang, only a brief blip is acceptable
- Latency at Balanced feels acceptable for real-time playing (no noticeable lag between pick attack and heard note)

- [ ] **Step 5: Record results**

If anything fails, note it — it becomes a new task/spec addendum, not a silent fix. If everything passes, the v1 plugin is functionally done.
