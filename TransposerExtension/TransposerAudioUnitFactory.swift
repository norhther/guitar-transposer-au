import CoreAudioKit

public class TransposerAudioUnitFactory: AUViewController, AUAudioUnitFactory {
    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        try AUAudioUnit(componentDescription: componentDescription)
    }
}
