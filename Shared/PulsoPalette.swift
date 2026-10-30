import SwiftUI

/// Single source of truth for Pulso's colours, compiled into the app and the widgets.
/// Each metric colour carries one meaning everywhere: never reuse one for a different signal.
enum PulsoPalette {
    // Surfaces (slate).
    static let background = Color(red: 0.067, green: 0.082, blue: 0.098)
    static let backgroundTop = Color(red: 0.149, green: 0.180, blue: 0.208)
    static let card = Color(red: 0.149, green: 0.176, blue: 0.200)
    static let cardHighlight = Color(red: 0.200, green: 0.231, blue: 0.259)

    /// Text on cards: secondary 6.9:1, tertiary 4.9:1 against `card` (WCAG AA).
    static let secondary = Color(white: 0.72)
    static let tertiary = Color(white: 0.60)

    // Recovery bands (same cut-offs as `Recovery.band`: 67 / 34).
    static let recoveryHigh = Color(red: 0.09, green: 0.93, blue: 0.02)
    static let recoveryMid = Color(red: 1.00, green: 0.87, blue: 0.00)
    static let recoveryLow = Color(red: 1.00, green: 0.18, blue: 0.27)

    static let strain = Color(red: 0.00, green: 0.58, blue: 0.91)
    static let sleep = Color(red: 0.48, green: 0.63, blue: 0.73)
    static let hrv = Color(red: 0.25, green: 0.70, blue: 0.95)
    static let stress = Color(red: 0.96, green: 0.65, blue: 0.14)
    static let stressLow = Color(red: 0.29, green: 0.64, blue: 0.94)
    static let stressMid = Color(red: 0.06, green: 0.83, blue: 0.61)
    static let stressHigh = stress
    static let better = Color(red: 0.10, green: 0.86, blue: 0.62)
    static let worse = stress
    static let link = Color(red: 0.45, green: 0.62, blue: 1.00)

    static let stageAwake = Color(white: 0.85)
    static let stageLight = Color(red: 0.66, green: 0.66, blue: 0.98)
    static let stageDeep = Color(red: 0.96, green: 0.55, blue: 0.94)
    static let stageREM = Color(red: 0.66, green: 0.32, blue: 0.95)

    static func recovery(_ score: Double?) -> Color {
        guard let score else { return secondary }
        return score >= 67 ? recoveryHigh : (score >= 34 ? recoveryMid : recoveryLow)
    }

    /// Heart-rate zones as an intensity ramp: cool → hot. 0 = rest.
    static func zone(_ zone: Int) -> Color {
        switch zone {
        case 1: return Color(red: 0.55, green: 0.75, blue: 1.0)
        case 2: return Color(red: 0.25, green: 0.85, blue: 0.55)
        case 3: return Color(red: 1.0, green: 0.80, blue: 0.20)
        case 4: return Color(red: 1.0, green: 0.50, blue: 0.20)
        case 5: return Color(red: 1.0, green: 0.25, blue: 0.30)
        default: return Color(white: 0.5)
        }
    }
}
