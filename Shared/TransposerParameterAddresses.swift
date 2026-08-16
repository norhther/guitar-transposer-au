import AudioToolbox

enum TransposerParameterAddress: AUParameterAddress {
    case semitones = 0
    case latencyMode = 1
    case formantSemitones = 2
    case formantCompensate = 3
    case advancedEnabled = 4
    case blockMilliseconds = 5
    case overlap = 6
    case tonalityLimit = 7
}
