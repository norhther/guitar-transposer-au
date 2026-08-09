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
        let audioUnit = self.audioUnit
        let hosting = UIHostingController(rootView: TransposerView(
            meter: meter,
            parameterTree: tree,
            initialBypassed: audioUnit.shouldBypassEffect,
            setBypassed: { audioUnit.shouldBypassEffect = $0 }
        ))
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
