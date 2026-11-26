import SwiftUI
import CoreText

/// Web `.edu-icon` parity — Material Symbols Outlined.
///
/// SwiftUI `Text` does **not** enable ligature substitution for custom fonts by
/// default, so rendering the icon *name* (e.g. `"mic"`) shows literal letters.
/// We instead emit the glyph's Private Use Area codepoint from the font cmap,
/// which reliably draws the symbol.
public struct EduIcon: View {
    let name: String
    var size: CGFloat = 20
    var filled: Bool = false
    var weight: Int = 400
    var tint: Color? = nil

    public init(_ name: String, size: CGFloat = 20, filled: Bool = false, weight: Int = 400, tint: Color? = nil) {
        self.name = name
        self.size = size
        self.filled = filled
        self.weight = weight
        self.tint = tint
    }

    public var body: some View {
        let _ = EduFontRegistrar.registerIfNeeded()
        Text(verbatim: glyphString)
            .font(Font.custom("MaterialSymbolsOutlined-Regular", size: size))
            .foregroundStyle(tint ?? .primary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: size, height: size, alignment: .center)
            .accessibilityHidden(true)
    }

    private var glyphString: String {
        if let scalar = EduIconCodepoints.scalar(for: name) {
            return String(scalar)
        }
        // Last resort: name as ligature text (only if host enables liga).
        return name
    }
}

/// PUA codepoints for Material Symbols Outlined (glyph name → cmap).
/// Sourced from `MaterialSymbolsOutlined.ttf` best cmap (first PUA per name).
enum EduIconCodepoints {
    private static let map: [String: UInt32] = [
        "arrow_back": 0xE5C4,
        "campaign": 0xEF49,
        "call_end": 0xE0B1,
        "chat": 0xE0B7,
        "check": 0xE5CA,
        "check_circle": 0xE86C,
        "chevron_left": 0xE408,
        "chevron_right": 0xE409,
        "circle": 0xEF4A,
        "close": 0xE14C,
        "delete_sweep": 0xE16C,
        "description": 0xE683,
        "edit": 0xE150,
        "expand_less": 0xE5CE,
        "expand_more": 0xE5CF,
        "extension": 0xE87B,
        "format_shapes": 0xE25E,
        "front_hand": 0xE769,
        "fullscreen": 0xE5D0,
        "fullscreen_exit": 0xE5D1,
        "gesture": 0xE155,
        "grid_view": 0xE9B0,
        "group": 0xE7EF,
        "keyboard_double_arrow_left": 0xEAC3,
        "keyboard_double_arrow_right": 0xEAC9,
        "mic": 0xE029,
        "mic_off": 0xE02B,
        "near_me": 0xE569,
        "notifications": 0xE7F4,
        "person": 0xE7FD,
        "pending": 0xEF64,
        "picture_as_pdf": 0xE415,
        "radio_button_unchecked": 0xE836,
        "rectangle": 0xEB54,
        "rocket_launch": 0xEB9B,
        "screen_rotation": 0xE1C1,
        "screen_share": 0xE0E2,
        "settings": 0xE8B8,
        "stay_current_landscape": 0xE0D3,
        "stay_current_portrait": 0xE0D4,
        "build": 0xE869,
        "slideshow": 0xE41B,
        "splitscreen_bottom": 0xF676,
        "splitscreen_left": 0xF675,
        "splitscreen_right": 0xF674,
        "splitscreen_top": 0xF673,
        "text_fields": 0xE262,
        "unfold_more": 0xE5D7,
        "videocam": 0xE04B,
        "videocam_off": 0xE04C,
        "view_agenda": 0xE8E9,
        "view_column": 0xE8EC,
        "view_module": 0xE8F0,
        "view_stream": 0xE8F2,
        "volume_up": 0xE050,
        "warning": 0xE002,
        "zoom_in": 0xE8FF,
        "zoom_out": 0xE900,
    ]

    static func scalar(for name: String) -> Unicode.Scalar? {
        guard let cp = map[name], let scalar = Unicode.Scalar(cp) else { return nil }
        return scalar
    }
}
