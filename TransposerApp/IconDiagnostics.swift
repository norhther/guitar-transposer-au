import SwiftUI
import AVFoundation
import AudioToolbox

/// Diagnostic probe for the missing AUv3 icon in hosts (AUM etc).
///
/// What we established from the iOS SDK headers + disassembly of
/// AudioToolboxCore (both APIs are thin wrappers over one virtual method in
/// GlobalComponentPluginMgr, so they share a single icon pipeline):
///   - `AudioComponentCopyIcon` (iOS 14+): "For a component originating in an
///     app extension, the returned icon will be that of the application
///     containing the extension." (Apple SDK doc)
///   - `AudioComponentGetIcon(_, size)` (deprecated): same pipeline, just
///     forwards a preferred point size.
/// So there is no separate "loose PNG in the appex" path on iOS — the icon is
/// the containing app's icon, resolved via IconServices at registration time.
///
/// This enumerates every installed AU and reports what BOTH public APIs
/// return. Results are also printed to stdout (tag AUPROBE) so they can be
/// captured via `devicectl device process launch --console`.
///
/// CRITICAL gotcha discovered during the investigation (2026-08-15): on
/// device, an app WITHOUT the `inter-app-audio` entitlement only sees Apple
/// system components — third-party AUv3s (including our own!) are invisible
/// to both `AVAudioUnitComponentManager` and `AudioComponentFindNext`, which
/// makes a perfectly-registered AU look "not registered" and its icon "nil".
/// Hosts like AUM carry the Inter-App Audio capability, so they see
/// everything. This app has the entitlement + audio background mode, so this
/// probe sees the full registry (535+ components) like a host would.
struct IconDiagnostics {
    struct Row: Identifiable {
        let id = UUID()
        let label: String
        /// Result of deprecated `AudioComponentGetIcon(_, 40)`.
        let getIconDetail: String
        /// Result of modern `AudioComponentCopyIcon(_)`.
        let copyIconDetail: String
        let isOurs: Bool

        var hasIcon: Bool { getIconDetail != "nil" || copyIconDetail != "nil" }

        var consoleLine: String {
            "\(hasIcon ? "OK " : "NIL") \(label) | GetIcon: \(getIconDetail) | CopyIcon: \(copyIconDetail)"
        }
    }

    /// Captured at app launch, BEFORE `ContentView` calls `AUAudioUnit.registerSubclass`.
    /// That call registers an in-process copy of aufx/gtrx/Nort which has no bundle on
    /// disk, so probing after it would report nil for our component no matter what the
    /// shipped appex contains.
    static let snapshot = run()

    static func run() -> [Row] {
        // Enumerate EVERYTHING, not just effects: a filtered query that misses our
        // component cannot distinguish "not registered" from "filter is wrong".
        let components = AVAudioUnitComponentManager.shared()
            .components(matching: AudioComponentDescription())

        let rows = directLookupRows() + components.map { component in
            let subtype = fourCharString(component.audioComponentDescription.componentSubType)
            let manufacturer = fourCharString(component.audioComponentDescription.componentManufacturer)
            let ours = subtype == "gtrx" && manufacturer == "Nort"

            return Row(
                label: "\(manufacturer).\(subtype) \(component.name)",
                getIconDetail: probe(component.audioComponent, via: .legacy),
                copyIconDetail: probe(component.audioComponent, via: .modern),
                isOurs: ours
            )
        }

        // Dump to stdout so results are capturable via
        // `devicectl device process launch --console` without UI interaction.
        let withIcon = rows.filter(\.hasIcon).count
        print("AUPROBE begin: \(withIcon)/\(rows.count) components returned an icon")
        for row in rows { print("AUPROBE \(row.consoleLine)") }
        print("AUPROBE end")
        fflush(stdout)

        return rows
    }

    private enum IconAPI {
        case legacy, modern
    }

    private static func probe(_ component: AudioComponent, via api: IconAPI = .legacy) -> String {
        let icon: UIImage?
        switch api {
        case .legacy:
            icon = AudioComponentGetIcon(component, 40)
        case .modern:
            icon = AudioComponentCopyIcon(component)
        }
        guard let icon = icon else { return "nil" }
        // A non-nil but 0x0 / uniformly blank image is the documented
        // "proxy with NULL bundle URL" failure mode, not a real icon.
        return "\(Int(icon.size.width))x\(Int(icon.size.height)) @\(icon.scale)x"
    }

    /// Looks our component up through the raw CoreAudio registry, bypassing
    /// `AVAudioUnitComponentManager` entirely. If this finds it but the manager does
    /// not, the manager's cache is the problem, not the appex registration.
    private static func directLookupRows() -> [Row] {
        var description = AudioComponentDescription()
        description.componentType = kAudioUnitType_Effect
        description.componentSubType = 0x67747278 // 'gtrx'
        description.componentManufacturer = 0x4E6F7274 // 'Nort'

        var rows: [Row] = []
        var found: AudioComponent? = AudioComponentFindNext(nil, &description)
        var index = 0

        while let component = found {
            var name: Unmanaged<CFString>?
            let status = AudioComponentCopyName(component, &name)
            let resolvedName = status == noErr
                ? (name?.takeRetainedValue() as String? ?? "<no name>")
                : "<name err \(status)>"

            rows.append(Row(
                label: "DIRECT[\(index)] \(resolvedName)",
                getIconDetail: probe(component, via: .legacy),
                copyIconDetail: probe(component, via: .modern),
                isOurs: true
            ))

            index += 1
            found = AudioComponentFindNext(component, &description)
        }

        if rows.isEmpty {
            rows.append(Row(
                label: "DIRECT: aufx/gtrx/Nort NOT FOUND in CoreAudio registry",
                getIconDetail: "nil",
                copyIconDetail: "nil",
                isOurs: true
            ))
        }
        return rows
    }

    private static func fourCharString(_ code: OSType) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}

struct IconDiagnosticsView: View {
    private let rows = IconDiagnostics.snapshot

    var body: some View {
        let withIcon = rows.filter(\.hasIcon).count

        return NavigationStack {
            List {
                Section("Summary") {
                    Text("\(withIcon) / \(rows.count) AUs returned an icon")
                        .font(.headline)
                }
                Section("Components") {
                    ForEach(rows) { row in
                        HStack(alignment: .top) {
                            Text(row.hasIcon ? "✅" : "❌")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.label)
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(row.isOurs ? .bold : .regular)
                                Text("GetIcon (legacy): \(row.getIconDetail)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("CopyIcon (modern): \(row.copyIconDetail)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("AU Icon Probe")
        }
    }
}
