import CoreAudioKit

public class TransposerAudioUnitFactory: AUViewController, AUAudioUnitFactory {
    private var audioUnit: TransposerAudioUnit?
    private var hostingController: TransposerViewController?

    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let audioUnit = try TransposerAudioUnit(componentDescription: componentDescription, options: [])
        self.audioUnit = audioUnit
        if Thread.isMainThread {
            installUIIfReady()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.installUIIfReady()
            }
        }
        return audioUnit
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 400, height: 300)
        installUIIfReady()
    }

    /// The host may call `createAudioUnit(with:)` and load this view controller's
    /// `viewDidLoad` in either order. This method is idempotent and safe to call from
    /// both places: it only installs the hosted UI once both the audio unit exists and
    /// the view has loaded, and never installs it twice.
    private func installUIIfReady() {
        guard isViewLoaded, let audioUnit = audioUnit, hostingController == nil else { return }
        let hosting = TransposerViewController(audioUnit: audioUnit)
        hostingController = hosting
        addChild(hosting)
        hosting.view.frame = view.bounds.isEmpty ? CGRect(origin: .zero, size: preferredContentSize) : view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }
}
