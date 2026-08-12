import SwiftUI
import AudioToolbox
import AVFoundation

struct ContentView: View {
    @State private var audioUnit: TransposerAudioUnit?
    @State private var loadError: String?
    private let engine = AVAudioEngine()

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
                guard let avAudioUnit = avAudioUnit else {
                    self.loadError = "No audio unit instance was returned"
                    return
                }
                self.audioUnit = avAudioUnit.auAudioUnit as? TransposerAudioUnit
                self.startEngine(with: avAudioUnit)
            }
        }
    }

    /// Wires the AU into a live mic -> transposer -> speaker graph. Without this the
    /// app instantiates the unit but never pulls audio through it — silent no-op.
    private func startEngine(with node: AVAudioUnit) {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard granted else {
                    self.loadError = "Microphone access denied"
                    return
                }
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothA2DP])
                    try session.setActive(true)

                    self.engine.attach(node)
                    let inputFormat = self.engine.inputNode.outputFormat(forBus: 0)
                    self.engine.connect(self.engine.inputNode, to: node, format: inputFormat)
                    self.engine.connect(node, to: self.engine.mainMixerNode, format: nil)
                    self.engine.prepare()
                    try self.engine.start()
                } catch {
                    self.loadError = error.localizedDescription
                }
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
