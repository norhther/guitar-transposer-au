# AUv3 icon missing in hosts (AUM) — investigation write-up

Date: 2026-08-15. Symptom: the standalone app showed its icon, but AUM and
other hosts listed Guitar Transposer with no icon. Fixed in commit
"fix: restore AUv3 icon and host visibility".

## TL;DR — how AUv3 icons actually work on iOS

Per the `AudioComponentCopyIcon` SDK docs: *"For a component originating in
an app extension, the returned icon will be that of the application
containing the extension."* The legacy `AudioComponentGetIcon(_, size)` is a
thin wrapper over the same pipeline (verified by disassembling
AudioToolboxCore — both call one shared internal method).

Consequences:

- The plugin icon in hosts = **the containing app's regular `AppIcon` asset
  catalog**. Nothing else is read.
- The `.appex` needs **no** icon keys, no asset catalog, no loose PNGs.
  (`CFBundleIconFile` + loose `Icon.png` shims were cargo cult and were
  removed.)
- The `AudioComponents` registration dict has no icon key.

## Root causes (there were three, stacked)

1. **The app had no app icon when hosts first saw it.** The first installed
   build (CFBundleVersion 1) shipped without `Assets.xcassets`, so the
   system-served AU icon was nil and hosts cached that state. The asset
   catalog was only added later.

2. **The diagnostic probe lied about registration.** On device, an app
   **without the `inter-app-audio` entitlement** can only enumerate Apple
   system components — third-party AUv3s (including its own extension!) are
   invisible to both `AVAudioUnitComponentManager` and
   `AudioComponentFindNext`. So the probe reported "NOT FOUND in CoreAudio
   registry" and "icon: nil" while AUM (which has the entitlement) listed
   the AU fine. An entire afternoon of "registration is blacklisted"
   hypotheses (reinstalls, reboot, AU version bump, appex bundle-ID change —
   none helped, because registration was never broken) came from this
   artifact. Tells that should have given it away sooner: the device probe
   saw fewer components than the simulator even among Apple's own AUs
   (SiriAUSP & friends are entitlement-filtered on device), and AUM listed
   Guitar Transposer the whole time.

3. **Build 1 was crashy, which poisoned host-visible state further.** Device
   crash logs (pulled via `devicectl device copy from --domain-type
   systemCrashLogs`) showed 8 × TransposerApp `EXC_BAD_ACCESS` "excessive
   recursion" crashes at launch, and 4 × AUM `0x8BADF00D` watchdog kills —
   AUM hung on an XPC call into the broken extension while loading it.
   Hosts remember a plugin that hangs them.

Related, already fixed earlier: `ENABLE_DEBUG_DYLIB=NO` must stay set —
Xcode 16+ Debug builds otherwise ship a blank launcher stub as the bundle
executable, which breaks the bundle-derived lookups (display name, icon)
that AUv3 registration depends on.

## The fix

- `TransposerApp.entitlements`: `inter-app-audio = true`, plus
  `UIBackgroundModes: audio`. Any app that wants to *see* or host
  third-party AUs needs this; the standalone app/probe included.
- Real `AppIcon` asset catalog on the containing app (the actual fix for
  the icon itself).
- AU component `version` 2→3 and `CFBundleVersion` 2→3: forces hosts and
  the AU registrar to re-read the registration instead of serving cached
  nil-icon state. (The appex bundle ID also changed to
  `com.norhther.guitartransposer.aufx` during diagnosis — kept, harmless,
  and gives hosts a fresh extension identity.)
- Removed the dead appex icon shims.
- `TransposerApp/IconDiagnostics.swift` ("Icon Probe" button, top-right in
  the app): probes BOTH icon APIs for every registered AU and prints rows
  tagged `AUPROBE` to stdout, capturable headless via
  `xcrun devicectl device process launch --device <udid> --console -t 25 <bundle-id>`.
  Remove the overlay button from `ContentView.swift` when no longer needed.

## Verified end state (on-device probe)

```
AUPROBE begin: 531/535 components returned an icon
AUPROBE OK  DIRECT[0] Norhther: Guitar Transposer | GetIcon: 136x136 | CopyIcon: 136x136
AUPROBE OK  Nort.gtrx Guitar Transposer          | GetIcon: 136x136 | CopyIcon: 136x136
```

535 visible components (vs 41 without the entitlement); the only NIL icons
are Apple-internal AUs (SiriAUSP, MauiAUSP, KonaSynthesizer, MacinTalkAUSP),
same as a clean simulator. AUM shows the icon after a restart.

## If a host still shows no icon

1. Force-quit and relaunch the host (it re-reads registrations on launch).
2. Confirm the containing app's home-screen icon renders — that is the same
   asset hosts get.
3. Run the Icon Probe: if our row is OK, the system serves the icon and the
   host is caching — reinstall the host or clear its plugin cache.
4. Bump the AU component `version` again to force every host to re-read.
