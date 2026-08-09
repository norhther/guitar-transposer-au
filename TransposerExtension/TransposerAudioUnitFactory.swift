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
