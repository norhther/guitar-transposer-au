import Foundation

/// Maps a semitone offset (-12...12) to a human-readable interval name,
/// e.g. 0 -> "Unison", 7 -> "+7 (Perfect 5th up)", -12 -> "-12 (Octave down)".
func intervalName(forSemitones semitones: Int) -> String {
    let names = [
        "Unison", "Minor 2nd", "Major 2nd", "Minor 3rd", "Major 3rd",
        "Perfect 4th", "Tritone", "Perfect 5th", "Minor 6th", "Major 6th",
        "Minor 7th", "Major 7th", "Octave"
    ]
    let clamped = max(-12, min(12, semitones))
    if clamped == 0 { return "Unison" }
    let name = names[abs(clamped)]
    let direction = clamped > 0 ? "up" : "down"
    let sign = clamped > 0 ? "+" : ""
    return "\(sign)\(clamped) (\(name) \(direction))"
}
