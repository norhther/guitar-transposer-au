import AudioToolbox

enum TransposerParameterAddress: AUParameterAddress {
    case semitones = 0
    case latencyMode = 1
    case formantSemitones = 2
    case formantCompensate = 3
}
