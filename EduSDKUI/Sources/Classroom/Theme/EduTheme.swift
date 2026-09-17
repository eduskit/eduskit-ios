import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Aligns with ui/web/src/styles/tokens.css
public enum EduColors {
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((value >> 16) & 0xff) / 255,
                green: CGFloat((value >> 8) & 0xff) / 255,
                blue: CGFloat(value & 0xff) / 255,
                alpha: 1
            )
        })
        #else
        return Color(hex: light)
        #endif
    }

    public static let surface = adaptive(light: 0xF8F9FF, dark: 0x101418)
    public static let surfaceBright = adaptive(light: 0xF8F9FF, dark: 0x252A30)
    public static let surfaceDim = adaptive(light: 0xCCDBF2, dark: 0x0B0F13)
    public static let surfaceLowest = adaptive(light: 0xFFFFFF, dark: 0x080B0E)
    public static let surfaceLow = adaptive(light: 0xEEF4FF, dark: 0x171C21)
    public static let surfaceContainer = adaptive(light: 0xE5EFFF, dark: 0x1B2026)
    public static let surfaceHigh = adaptive(light: 0xDBE9FF, dark: 0x252B32)
    public static let surfaceHighest = adaptive(light: 0xD4E4FA, dark: 0x30363D)
    public static let surfaceVariant = surfaceHighest
    public static let onSurface = adaptive(light: 0x0D1C2D, dark: 0xEDF1F5)
    public static let onSurfaceVariant = adaptive(light: 0x46474A, dark: 0xC0C7CF)
    public static let outline = adaptive(light: 0x76777B, dark: 0x9199A2)
    public static let outlineVariant = adaptive(light: 0xC7C6CA, dark: 0x424951)
    public static let primary = adaptive(light: 0x000000, dark: 0xFFFFFF)
    public static let onPrimary = adaptive(light: 0xFFFFFF, dark: 0x111418)
    public static let primaryContainer = adaptive(light: 0x1B1B1C, dark: 0xE3E7EB)
    public static let secondary = adaptive(light: 0x505F76, dark: 0xBDC7D5)
    public static let onSecondary = adaptive(light: 0xFFFFFF, dark: 0x202832)
    public static let secondaryContainer = adaptive(light: 0xD0E1FB, dark: 0x344252)
    public static let onSecondaryContainer = adaptive(light: 0x54647A, dark: 0xD9E5F5)
    public static let error = adaptive(light: 0xBA1A1A, dark: 0xFFB4AB)
    public static let onError = adaptive(light: 0xFFFFFF, dark: 0x690005)
    public static let live = adaptive(light: 0xBA1A1A, dark: 0xFFB4AB)
    public static let onLive = adaptive(light: 0xFFFFFF, dark: 0x690005)
    public static let success = adaptive(light: 0x16A34A, dark: 0x6DDD8B)
    public static let warning = adaptive(light: 0xD97706, dark: 0xFFB95C)
    public static let chipBg = adaptive(light: 0xF1F5F9, dark: 0x252B32)
    public static let glassFill = surfaceLowest.opacity(0.92)
    public static let scrim = Color(hex: 0x0F172A, opacity: 0.28)
}

public enum EduDimens {
    public static let unit: CGFloat = 8
    public static let stackSm: CGFloat = 8
    public static let stackMd: CGFloat = 16
    public static let stackLg: CGFloat = 32
    public static let stackXl: CGFloat = 64
    public static let gutter: CGFloat = 24
    public static let marginDesktop: CGFloat = 64
    public static let sidebarWidth: CGFloat = 320
    public static let headerHeight: CGFloat = 64
    public static let headerHeightPhone: CGFloat = 56
    public static let stripHeight: CGFloat = 136
    public static let videoTileW: CGFloat = 220
    public static let videoTileH: CGFloat = 124
    public static let videoGap: CGFloat = 16
    public static let tileAvatarSize: CGFloat = 56
    public static let tileAvatarSizeFeatured: CGFloat = 72
    public static let tileAvatarSizeCompact: CGFloat = 48
    public static let tileAvatarSizePip: CGFloat = 32
    public static let tileAvatarFont: CGFloat = 18
    public static let tileAvatarFontFeatured: CGFloat = 24
    public static let tileAvatarFontCompact: CGFloat = 16
    public static let tileAvatarFontPip: CGFloat = 12
    public static let floatBtnW: CGFloat = 64
    public static let floatBtnH: CGFloat = 56
    public static let floatBtnRadius: CGFloat = 12
    public static let phoneBreakpoint: CGFloat = 768
    public static let bloomCardW: CGFloat = 132
    public static let pipSize: CGFloat = 56
    public static let radius: CGFloat = 2
    public static let radiusLg: CGFloat = 4
    public static let radiusXl: CGFloat = 8
    public static let radius2xl: CGFloat = 12
    public static let radiusFull: CGFloat = 12

    /// Sidebar vertical strip: 2.5 tiles + gaps
    public static var sidebarStripHeight: CGFloat {
        videoTileH * 2.5 + videoGap * 2
    }
}

public enum EduFont {
    public static let brand = Font.custom("HankenGrotesk-SemiBold", size: 24)
        .weight(.semibold)
    public static let title = Font.custom("HankenGrotesk-SemiBold", size: 14)
    public static let badge = Font.custom("HankenGrotesk-SemiBold", size: 10)
    public static let floatLabel = Font.custom("HankenGrotesk-SemiBold", size: 10)
    /// 白板面板 section 标签 — Web `.edu-panel__label`
    public static let panelSection = Font.custom("HankenGrotesk-Medium", size: 11)
    /// 白板面板标题
    public static let panelTitle = Font.custom("HankenGrotesk-SemiBold", size: 13)

    public static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "HankenGrotesk-Bold"
        case .semibold, .medium: name = weight == .medium ? "HankenGrotesk-Medium" : "HankenGrotesk-SemiBold"
        default: name = "HankenGrotesk-Regular"
        }
        return Font.custom(name, size: size)
    }
}

public enum EduMotion {
    public static let floatExpand: Double = 0.32
    public static let sidebar: Double = 0.28
    public static let flipMin: Double = 0.48
    public static let flipMax: Double = 0.78
    public static let bloom: Double = 0.32
    public static let bloomStagger: Double = 0.042
    public static let modal: Double = 0.22
    /// 白板面板开合 / swap / 锚点（对齐 Web AnnotationToolbar）
    public static let panelOpen: Double = 0.28
    public static let panelFadeIn: Double = 0.18
    public static let panelFadeOut: Double = 0.14
    public static let panelCloseFade: Double = 0.20
    public static let panelSwapMorph: Double = 0.30
    public static let panelAnchor: Double = 0.32
    public static let panelPreview: Double = 0.15
    public static let ease = Animation.timingCurve(0.4, 0, 0.2, 1, duration: floatExpand)
    public static func ease(_ duration: Double) -> Animation {
        Animation.timingCurve(0.4, 0, 0.2, 1, duration: duration)
    }

    /// FLIP `cubic-bezier(0.22, 1, 0.36, 1)`.
    public static func flip(_ duration: Double = flipMin + 0.08) -> Animation {
        Animation.timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }
}

// MARK: - Elevation tokens (1:1 with Web --edu-shadow-*)

/// - soft   ≈ 0 4px 20px -2px rgba(0,0,0,0.05)
/// - level2 ≈ 0 4px 12px rgba(0,0,0,0.03)
/// - level3 ≈ 0 12px 32px rgba(0,0,0,0.08)
/// - md     ≈ 0 4px 6px rgba(0,0,0,0.10) + 0 2px 4px rgba(0,0,0,0.10)
/// - panel  ≈ Web 双层 slate：0 6 24 -6 / 0 2 8 -2 rgba(15,23,42,…)
public enum EduElevation { case soft, level2, level3, md, panel }

public struct EduShadowModifier: ViewModifier {
    var tier: EduElevation
    public func body(content: Content) -> some View {
        switch tier {
        case .soft:
            content.shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        case .level2:
            content.shadow(color: .black.opacity(0.03), radius: 8, y: 4)
        case .level3:
            content.shadow(color: .black.opacity(0.08), radius: 16, y: 8)
        case .md:
            content
                .shadow(color: .black.opacity(0.10), radius: 3, y: 4)
                .shadow(color: .black.opacity(0.10), radius: 2, y: 2)
        case .panel:
            content
                .shadow(color: Color(hex: 0x0F172A, opacity: 0.14), radius: 12, y: 6)
                .shadow(color: Color(hex: 0x0F172A, opacity: 0.06), radius: 4, y: 2)
        }
    }
}

public extension View {
    func eduShadow(_ tier: EduElevation) -> some View { modifier(EduShadowModifier(tier: tier)) }

    /// Float-bar `level3` + tinted `rgba(13,28,45,0.06) r8 y2` — Web double stack.
    func eduFloatBarShadow() -> some View {
        self
            .shadow(color: Color(hex: 0x0D1C2D, opacity: 0.06), radius: 4, y: 2)
            .eduShadow(.level3)
    }

    /// 白板配置面板双层阴影。
    func eduPanelShadow() -> some View { eduShadow(.panel) }
}

// MARK: - Color mixing (Web `color-mix(in srgb, A ratio%, B)`)

public extension Color {
    /// sRGB linear blend — `self * (1-r) + with * r`.
    /// Equivalent to Web `color-mix(in srgb, self (1-r)%, with r%)`.
    func mix(with other: Color, ratio: CGFloat) -> Color {
        let r = min(max(ratio, 0), 1)
        let inv = 1 - r
        // Extract sRGB components via UIColor bridge (SwiftUI Color is opaque).
        let (r1, g1, b1, a1) = other.rgba
        let (r0, g0, b0, a0) = self.rgba
        return Color(
            .sRGB,
            red: Double(r0 * inv + r1 * r),
            green: Double(g0 * inv + g1 * r),
            blue: Double(b0 * inv + b1 * r),
            opacity: Double(a0 * inv + a1 * r)
        )
    }

    /// Web `color-mix(in srgb, self N%, transparent)` → alpha N%.
    func tint(_ alpha: CGFloat) -> Color { opacity(Double(alpha)) }

    fileprivate var rgba: (CGFloat, CGFloat, CGFloat, CGFloat) {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
        #else
        return (0, 0, 0, 1)
        #endif
    }
}

public enum EduTint {
    public static let surfaceLow20 = EduColors.surfaceLow.tint(0.20)
    public static let surfaceLow30 = EduColors.surfaceLow.tint(0.30)
    public static let surfaceLow50 = EduColors.surfaceLow.tint(0.50)
    public static let surfaceLowest50 = EduColors.surfaceLowest.tint(0.50)
    public static let onSurface10 = EduColors.onSurface.tint(0.10)
    public static let onSurface40 = EduColors.onSurface.tint(0.40)
    public static let onSurfaceVariant30 = EduColors.onSurfaceVariant.tint(0.30)
    public static let onSurfaceVariant40 = EduColors.onSurfaceVariant.tint(0.40)
    public static let outlineVariant45 = EduColors.outlineVariant.tint(0.45)
    public static let outlineVariant30 = EduColors.outlineVariant.tint(0.30)
    public static let outlineVariant20 = EduColors.outlineVariant.tint(0.20)
    public static let errorTint8 = EduColors.error.tint(0.08)
    public static let primaryRing35 = EduColors.primary.tint(0.35)
    public static let primaryRing22 = EduColors.primary.tint(0.22)
    public static let whiteRing35 = Color.white.tint(0.35)
    public static let chipShadow = Color(hex: 0x0F172A, opacity: 0.08)
}

/// Glass surface ≈ Web 92% surface + `backdrop-filter: blur(12–14px)` + elevation.
/// SwiftUI `.ultraThinMaterial` provides live backdrop blur; we overlay the tinted
/// surface (92% by default) and the 1px border.
public struct EduGlassBackground: ViewModifier {
    var cornerRadius: CGFloat = EduDimens.radius2xl
    var borderColor: Color = EduColors.surfaceLow
    var tier: EduElevation = .soft
    var surface: Color = EduColors.surfaceLowest
    var surfaceAlpha: Double = 0.92

    public func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(surface.opacity(surfaceAlpha)))
                    .overlay(shape.stroke(borderColor, lineWidth: 1))
                    .eduShadow(tier)
            }
    }
}

public extension View {
    func eduGlass(
        cornerRadius: CGFloat = EduDimens.radius2xl,
        borderColor: Color = EduColors.surfaceLow,
        tier: EduElevation = .soft,
        surface: Color = EduColors.surfaceLowest,
        surfaceAlpha: Double = 0.92
    ) -> some View {
        modifier(EduGlassBackground(
            cornerRadius: cornerRadius,
            borderColor: borderColor,
            tier: tier,
            surface: surface,
            surfaceAlpha: surfaceAlpha
        ))
    }

}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// iOS 15–compatible uneven rounded rect (avoids UnevenRoundedRectangle).
struct EduRoundedCorners: Shape {
    var topLeading: CGFloat = 0
    var bottomLeading: CGFloat = 0
    var bottomTrailing: CGFloat = 0
    var topTrailing: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let w = rect.size.width
        let h = rect.size.height
        let tr = min(min(topTrailing, h / 2), w / 2)
        let tl = min(min(topLeading, h / 2), w / 2)
        let bl = min(min(bottomLeading, h / 2), w / 2)
        let br = min(min(bottomTrailing, h / 2), w / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                radius: tr,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        if br > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                radius: br,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                radius: bl,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                radius: tl,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        }
        path.closeSubpath()
        return path
    }
}

/// 读取当前 key window 的系统 Safe Area。
/// `GeometryReader.safeAreaInsets` 在 `.ignoresSafeArea()` 后偶发为 0，UIKit 窗口值更稳。
enum EduSafeArea {
    struct Insets: Equatable {
        var top: CGFloat
        var bottom: CGFloat
        var leading: CGFloat
        var trailing: CGFloat
    }

    static var current: Insets {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first(where: { $0.activationState == .foregroundActive })
        let window = active?.windows.first(where: \.isKeyWindow)
            ?? active?.windows.first
            ?? scenes.flatMap(\.windows).first
        let raw = window?.safeAreaInsets ?? .zero
        return Insets(
            top: raw.top,
            bottom: raw.bottom,
            leading: raw.left,
            trailing: raw.right
        )
        #else
        return Insets(top: 0, bottom: 0, leading: 0, trailing: 0)
        #endif
    }

    static var bottomInset: CGFloat { current.bottom }

    /// 与 GeometryProxy 取较大值，避免全屏 bleed 后某一端读成 0。
    static func merge(with geo: GeometryProxy) -> Insets {
        let win = current
        return Insets(
            top: max(geo.safeAreaInsets.top, win.top),
            bottom: max(geo.safeAreaInsets.bottom, win.bottom),
            leading: max(geo.safeAreaInsets.leading, win.leading),
            trailing: max(geo.safeAreaInsets.trailing, win.trailing)
        )
    }

    /// 横屏水平避让：只垫硬件「顶部」（刘海 / Dynamic Island），对侧（原底部）贴边充满。
    ///
    /// 竖屏的 top safe area 转到横屏后成为 left **或** right 中较大的那一侧；
    /// 另一侧对应原 bottom，应强制为 0，不要两侧都垫。
    struct LandscapeHorizontalPads: Equatable {
        var leading: CGFloat
        var trailing: CGFloat
    }

    /// 判定「有刘海的一侧」的最小差值，避免两侧因圆角都有小 inset 时误判。
    private static let landscapeNotchSideMinDelta: CGFloat = 8

    static func landscapeHorizontalPads(insets: Insets) -> LandscapeHorizontalPads {
        let delta = insets.leading - insets.trailing
        if delta > landscapeNotchSideMinDelta {
            // 刘海在 leading（横屏后的设备顶部）
            return LandscapeHorizontalPads(leading: insets.leading, trailing: 0)
        }
        if delta < -landscapeNotchSideMinDelta {
            // 刘海在 trailing
            return LandscapeHorizontalPads(leading: 0, trailing: insets.trailing)
        }
        // 两侧接近：按界面方向兜底（UIKit：landscapeLeft ≈ 刘海在 trailing）
        #if canImport(UIKit)
        switch interfaceOrientation {
        case .landscapeLeft:
            return LandscapeHorizontalPads(leading: 0, trailing: insets.trailing)
        case .landscapeRight:
            return LandscapeHorizontalPads(leading: insets.leading, trailing: 0)
        default:
            return LandscapeHorizontalPads(leading: 0, trailing: 0)
        }
        #else
        return LandscapeHorizontalPads(leading: 0, trailing: 0)
        #endif
    }

    #if canImport(UIKit)
    private static var interfaceOrientation: UIInterfaceOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first
        return active?.interfaceOrientation ?? .unknown
    }
    #endif
}

/// GeometryReader → Preference 传递底部 Safe Area inset。
struct EduSafeAreaBottomInsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
