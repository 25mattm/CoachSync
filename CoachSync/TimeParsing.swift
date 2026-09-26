/// Shared helpers for formatting and parsing race and training times.
import Foundation

/// Formats millisecond values using `M:SS.CS` or `H:MM:SS.CS` for longer durations.
func formatMillisecondsForDisplay(_ milliseconds: Int) -> String {
    let clampedMilliseconds = max(milliseconds, 0)
    let totalSeconds = clampedMilliseconds / 1000
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    let centiseconds = (clampedMilliseconds % 1000) / 10

    if hours > 0 {
        return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds)
    }

    let totalMinutes = totalSeconds / 60
    return String(format: "%d:%02d.%02d", totalMinutes, seconds, centiseconds)
}

/// Formats seconds by rounding to the nearest millisecond first.
func formatSecondsForDisplay(_ seconds: Double) -> String {
    let totalMs = Int((seconds * 1000).rounded())
    return formatMillisecondsForDisplay(totalMs)
}

/// Formats milliseconds as a coarse `M:SS` (or `H:MM:SS`) label with no
/// centiseconds — for compact chart axis labels. Rounds to the nearest second.
func formatMillisecondsCoarse(_ milliseconds: Int) -> String {
    let totalSeconds = Int((Double(max(milliseconds, 0)) / 1000).rounded())
    let seconds = totalSeconds % 60
    let hours = totalSeconds / 3600
    if hours > 0 {
        let minutes = (totalSeconds % 3600) / 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", totalSeconds / 60, seconds)
}

// MARK: - Block-duration labels

/// Formats a block/rep duration in whole seconds as a compact label:
/// "45s", "10 min", or "2:30". Single shared copy — used by block summary
/// rows and the structural-block checkpoint so the wording can't drift.
func formatDurationLabel(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    if m == 0 { return "\(s)s" }
    if s == 0 { return "\(m) min" }
    return "\(m):\(String(format: "%02d", s))"
}

/// Formats a duration as a chip-style label using minute/second marks:
/// "4'", "1'30\"", "30\"". Single shared copy — used by pyramid chips, the
/// duration editor, block auto-names, and rep checkboxes.
func formatChipDuration(_ seconds: Int) -> String {
    if seconds >= 60 {
        let m = seconds / 60
        let s = seconds % 60
        if s == 0 { return "\(m)'" }
        return "\(m)'\(s)\""
    }
    return "\(seconds)\""
}

/// Parses time strings such as `M:SS.xx`, `M:SS.xxx`, `SS.xx`, `H:MM:SS.xxx`, or `H:MM:SS:MMM` into milliseconds.
func parseTimeToMs(_ input: String) -> Int? {
    let s = input.trimmingCharacters(in: .whitespaces)
    guard !s.isEmpty else { return nil }

    if s.contains(":") {
        let parts = s.components(separatedBy: ":")
        if parts.count == 2 {
            guard let minutes = Int(parts[0]),
                  minutes >= 0,
                  let (seconds, milliseconds) = parseSecondsComponent(parts[1]) else { return nil }
            return ((minutes * 60) + seconds) * 1000 + milliseconds
        } else if parts.count == 3 {
            guard let hours = Int(parts[0]),
                  let minutes = Int(parts[1]),
                  hours >= 0,
                  (0..<60).contains(minutes),
                  let (seconds, milliseconds) = parseSecondsComponent(parts[2]) else { return nil }
            return ((hours * 3600) + (minutes * 60) + seconds) * 1000 + milliseconds
        } else if parts.count == 4 {
            guard let hours = Int(parts[0]),
                  let minutes = Int(parts[1]),
                  let seconds = Int(parts[2]),
                  let milliseconds = parseMillisecondsComponent(parts[3]),
                  hours >= 0,
                  (0..<60).contains(minutes),
                  (0..<60).contains(seconds) else { return nil }
            return ((hours * 3600) + (minutes * 60) + seconds) * 1000 + milliseconds
        }
    } else if s.contains(".") {
        guard let (seconds, milliseconds) = parseSecondsComponent(s) else { return nil }
        return seconds * 1000 + milliseconds
    } else if let seconds = Int(s), seconds >= 0 {
        return seconds * 1000
    }
    return nil
}

/// Parses the seconds component and normalizes 1-3 fractional digits into milliseconds.
private func parseSecondsComponent(_ input: String) -> (seconds: Int, milliseconds: Int)? {
    let parts = input.components(separatedBy: ".")
    guard parts.count <= 2, let wholeSeconds = Int(parts[0]) else { return nil }
    guard (0..<60).contains(wholeSeconds) else { return nil }

    let milliseconds: Int
    if let fractionalPart = parts.dropFirst().first {
        // Reject over-precise input instead of silently truncating a coach-entered time.
        guard !fractionalPart.isEmpty,
              fractionalPart.count <= 3,
              fractionalPart.allSatisfy({ $0.isNumber }) else { return nil }

        guard let fractionValue = Int(fractionalPart) else { return nil }
        switch fractionalPart.count {
        case 1:
            milliseconds = fractionValue * 100
        case 2:
            milliseconds = fractionValue * 10
        default:
            milliseconds = fractionValue
        }
    } else {
        milliseconds = 0
    }

    return (wholeSeconds, milliseconds)
}

/// Parses a 1-3 digit millisecond component from a colon-separated time string.
private func parseMillisecondsComponent(_ input: String) -> Int? {
    guard !input.isEmpty, input.count <= 3, input.allSatisfy(\.isNumber),
          let milliseconds = Int(input) else { return nil }

    switch input.count {
    case 1:
        return milliseconds * 100
    case 2:
        return milliseconds * 10
    default:
        return milliseconds
    }
}
