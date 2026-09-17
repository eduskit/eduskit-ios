import Foundation
import SwiftUI

enum AnnotationDefaults {
    static let swatches: [String] = [
        "#000000", "#ffffff", "#ef4444", "#f97316", "#eab308",
        "#22c55e", "#3b82f6", "#2563eb", "#8b5cf6", "#ec4899",
    ]

    /// 对齐 Web HighlighterPanel 专用色板
    static let highlighterSwatches: [String] = [
        "#ffff00", "#fde047", "#f97316", "#ef4444", "#84cc16",
        "#22c55e", "#06b6d4", "#3b82f6", "#a855f7", "#ec4899",
    ]

    /// 对齐 Web TextPanel FONTS
    static let textFonts: [String] = [
        "sans-serif",
        "serif",
        "monospace",
        "Hanken Grotesk",
        "system-ui",
    ]

    static func penDiameter(_ thin: Int) -> CGFloat { max(0.5, CGFloat(thin) / 100 * 10) }
    static func highlighterDiameter(_ thin: Int) -> CGFloat { penDiameter(thin) * 2 }
    static func eraserDiameter(_ size: Int) -> CGFloat { max(2, CGFloat(size) / 100 * 24) }
    static func laserDiameter(_ size: Int) -> CGFloat { max(4, CGFloat(size) / 100 * 24) }
    static let laserHalo: CGFloat = 2.2
    static let highlighterAlpha: Double = 0.35

    static func color(from hex: String) -> Color {
        let raw = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)
        if raw.count == 8 {
            return Color(
                .sRGB,
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255,
                opacity: Double((value >> 24) & 0xFF) / 255
            )
        }
        return Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
