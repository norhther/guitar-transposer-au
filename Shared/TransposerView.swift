import SwiftUI
import AudioToolbox

struct TransposerView: View {
    @ObservedObject var meter: PeakMeterStore
    let parameterTree: AUParameterTree
    let initialBypassed: Bool
    let setBypassed: (Bool) -> Void

    @State private var semitones: Double = 0
    @State private var latencyModeIndex: Double = 1
    @State private var formantSemitones: Double = 0
    @State private var formantCompensate: Bool = false
    @State private var bypassed: Bool = false
    @State private var advancedEnabled: Bool = false
    @State private var blockMilliseconds: Double = 90
    @State private var overlap: Double = 4
    @State private var tonalityLimit: Double = 0
    @State private var observerToken: AUParameterObserverToken?

    private var semitonesParam: AUParameter { parameterTree.parameter(withAddress: TransposerParameterAddress.semitones.rawValue)! }
    private var latencyModeParam: AUParameter { parameterTree.parameter(withAddress: TransposerParameterAddress.latencyMode.rawValue)! }
    private var formantSemitonesParam: AUParameter { parameterTree.parameter(withAddress: TransposerParameterAddress.formantSemitones.rawValue)! }
    private var formantCompensateParam: AUParameter { parameterTree.parameter(withAddress: TransposerParameterAddress.formantCompensate.rawValue)! }
    private var advancedEnabledParam: AUParameter { parameterTree.parameter(withAddress: TransposerParameterAddress.advancedEnabled.rawValue)! }
    private var blockMillisecondsParam: AUParameter { parameterTree.parameter(withAddress: TransposerParameterAddress.blockMilliseconds.rawValue)! }
    private var overlapParam: AUParameter { parameterTree.parameter(withAddress: TransposerParameterAddress.overlap.rawValue)! }
    private var tonalityLimitParam: AUParameter { parameterTree.parameter(withAddress: TransposerParameterAddress.tonalityLimit.rawValue)! }

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

            Toggle("Advanced", isOn: $advancedEnabled)
                .onChange(of: advancedEnabled) { newValue in
                    advancedEnabledParam.value = newValue ? 1 : 0
                }

            if advancedEnabled {
                VStack(alignment: .leading) {
                    Text("Block: \(Int(blockMilliseconds)) ms")
                    Slider(value: $blockMilliseconds, in: 20...200, step: 5)
                        .onChange(of: blockMilliseconds) { newValue in
                            blockMillisecondsParam.value = AUValue(newValue)
                        }

                    Text("Overlap: \(String(format: "%.1fx", overlap))")
                    Slider(value: $overlap, in: 2...8, step: 0.5)
                        .onChange(of: overlap) { newValue in
                            overlapParam.value = AUValue(newValue)
                        }

                    Text("Tonality Limit: \(String(format: "%.2f", tonalityLimit))")
                    Slider(value: $tonalityLimit, in: 0...2, step: 0.05)
                        .onChange(of: tonalityLimit) { newValue in
                            tonalityLimitParam.value = AUValue(newValue)
                        }
                }
            } else {
                Picker("Latency Mode", selection: $latencyModeIndex) {
                    Text("Fast").tag(0.0)
                    Text("Balanced").tag(1.0)
                    Text("Quality").tag(2.0)
                }
                .pickerStyle(.segmented)
                .onChange(of: latencyModeIndex) { newValue in
                    latencyModeParam.value = AUValue(newValue)
                }
            }

            Stepper(value: $formantSemitones, in: -12...12, step: 1) {
                Text("Formant: \(Int(formantSemitones))")
            }
            .onChange(of: formantSemitones) { newValue in
                formantSemitonesParam.value = AUValue(newValue)
            }

            Toggle("Compensate Formant", isOn: $formantCompensate)
                .onChange(of: formantCompensate) { newValue in
                    formantCompensateParam.value = newValue ? 1 : 0
                }

            Toggle("Bypass", isOn: $bypassed)
                .onChange(of: bypassed) { newValue in
                    setBypassed(newValue)
                }

            HStack {
                MeterBar(label: "In", level: meter.inputLevel)
                MeterBar(label: "Out", level: meter.outputLevel)
            }
        }
        .padding()
        .onAppear {
            semitones = Double(semitonesParam.value)
            latencyModeIndex = Double(latencyModeParam.value)
            formantSemitones = Double(formantSemitonesParam.value)
            formantCompensate = formantCompensateParam.value != 0
            bypassed = initialBypassed
            advancedEnabled = advancedEnabledParam.value != 0
            blockMilliseconds = Double(blockMillisecondsParam.value)
            overlap = Double(overlapParam.value)
            tonalityLimit = Double(tonalityLimitParam.value)
            observerToken = parameterTree.token(byAddingParameterObserver: { address, value in
                DispatchQueue.main.async {
                    switch TransposerParameterAddress(rawValue: address) {
                    case .semitones: semitones = Double(value)
                    case .latencyMode: latencyModeIndex = Double(value)
                    case .formantSemitones: formantSemitones = Double(value)
                    case .formantCompensate: formantCompensate = value != 0
                    case .advancedEnabled: advancedEnabled = value != 0
                    case .blockMilliseconds: blockMilliseconds = Double(value)
                    case .overlap: overlap = Double(value)
                    case .tonalityLimit: tonalityLimit = Double(value)
                    case .none: break
                    }
                }
            })
        }
        .onDisappear {
            if let observerToken {
                parameterTree.removeParameterObserver(observerToken)
            }
            observerToken = nil
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
