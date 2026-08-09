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
