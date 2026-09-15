import SwiftUI
import TokenMeterCore

extension UsageLevel {
    /// Yellow → orange → red as a window nears its limit; nil below 50% so normal usage stays neutral.
    /// Light appearance gets darker shades so colored text stays legible on a light menu bar or panel.
    func tint(dark: Bool) -> Color? {
        switch self {
        case .normal: return nil
        case .elevated: return dark ? Color(red: 1, green: 0.84, blue: 0.04) : Color(red: 0.65, green: 0.49, blue: 0)
        case .high: return dark ? Color(red: 1, green: 0.62, blue: 0.04) : Color(red: 0.83, green: 0.37, blue: 0)
        case .critical: return dark ? Color(red: 1, green: 0.27, blue: 0.23) : Color(red: 0.84, green: 0, blue: 0.08)
        }
    }
}
