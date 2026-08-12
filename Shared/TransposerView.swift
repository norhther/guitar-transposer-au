import SwiftUI
import AudioToolbox

struct TransposerView: View {
    @ObservedObject var meter: PeakMeterStore
    let parameterTree: AUParameterTree
    let initialBypassed: Bool
    let setBypassed: (Bool) -> Void

    @State private var semitones: Double = 0
    @State private var latencyModeIndex: Double = 1
    @State private var bypassed: Bool = false
    @State private var observerToken: AUParameterObserverToken?

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
            bypassed = initialBypassed
            observerToken = parameterTree.token(byAddingParameterObserver: { address, value in
                DispatchQueue.main.async {
                    switch TransposerParameterAddress(rawValue: address) {
                    case .semitones: semitones = Double(value)
                    case .latencyMode: latencyModeIndex = Double(value)
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
