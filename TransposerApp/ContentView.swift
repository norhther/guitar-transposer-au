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
