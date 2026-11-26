import SwiftUI
import CoreText

enum EduFontRegistrar {
    private static var didRegister = false

    /// Register bundled `.ttf` fonts (Hanken + Material Symbols) into the process.
    /// SPM `.process("Resources")` flattens files into the bundle root (no `Fonts/` subdir).
    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        let names = [
            "HankenGrotesk-Regular",
            "HankenGrotesk-Medium",
            "HankenGrotesk-SemiBold",
            "HankenGrotesk-Bold",
            "MaterialSymbolsOutlined",
        ]
        let bundle = Bundle.module
        for name in names {
            let url = bundle.url(forResource: name, withExtension: "ttf")
            guard let url else { continue }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }
}

/// 薄壳：委托到完整白板工具栏 `AnnotationToolbarStackView`。
/// 保留此签名以避免 Desktop / Landscape / Mobile layout 改调用点。
struct AnnotationToolbarView: View {
    var mobile: Bool = false

    var body: some View {
        AnnotationToolbarStackView(mobile: mobile, showGlobalOps: !mobile)
    }
}

struct CtrlBtnView: View {
    let icon: String
    var label: String? = nil
    var active: Bool = false
    var danger: Bool = false
    var off: Bool = false
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        let tint: Color = {
            if danger { return EduColors.onError }
            if off { return EduColors.error }
            if active { return EduColors.primary }
            return EduColors.secondary
        }()
        let bg: Color = {
            if danger { return EduColors.error }
            if active { return EduColors.surfaceLow }
            if off { return EduTint.errorTint8 }
            return .clear
        }()
        Button(action: action) {
            VStack(spacing: 2) {
                EduIcon(icon, size: 24, tint: tint)
                if let label {
                    Text(label)
                        .font(EduFont.floatLabel)
                        .tracking(0.5)
                        .foregroundStyle(tint)
                }
            }
            .frame(width: EduDimens.floatBtnW, height: EduDimens.floatBtnH)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: EduDimens.floatBtnRadius, style: .continuous))
            .if(danger) { $0.eduShadow(.md) }
        }
        .buttonStyle(EduPressButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(Text(label ?? icon))
    }
}

private extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, @ViewBuilder transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

struct LayoutPopupView: View {
    let selected: VideoLayout
    var onSelect: (VideoLayout) -> Void

    private let items: [(VideoLayout, String, String)] = [
        (.top, EduIcons.splitscreenTop, EduI18n.text("layoutTop")),
        (.bottom, EduIcons.splitscreenBottom, EduI18n.text("layoutBottom")),
        (.rightTop, EduIcons.splitscreenRight, EduI18n.text("layoutRightTop")),
        (.rightBottom, EduIcons.splitscreenLeft, EduI18n.text("layoutRightBottom")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: EduDimens.unit) {
            ForEach(items, id: \.0) { layout, icon, label in
                let active = layout == selected
                Button {
                    onSelect(layout)
                } label: {
                    HStack(spacing: EduDimens.stackSm) {
                        EduIcon(
                            icon,
                            size: 20,
                            tint: active ? EduColors.primary : EduColors.onSurfaceVariant
                        )
                        Text(label)
                            .font(EduFont.title)
                            .tracking(0.5)
                            .foregroundStyle(active ? EduColors.primary : EduColors.onSurface)
                        Spacer(minLength: 0)
                    }
                    .padding(EduDimens.stackSm)
                    .background(active ? EduColors.primary.opacity(0.05) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: EduDimens.radiusLg)
                            .stroke(active ? EduColors.primary.opacity(0.2) : Color.clear, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: EduDimens.radiusLg))
                }
                .buttonStyle(EduPressButtonStyle(scale: 0.96))
            }
        }
        .padding(EduDimens.unit)
        .frame(width: 192)
        .eduGlass(cornerRadius: EduDimens.radiusXl, borderColor: EduColors.surfaceLow, tier: .level3)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

struct FloatingToolbarView: View {
    let videoLayout: VideoLayout
    let videoWallOpen: Bool
    var coursewareOpen: Bool = false
    var onVideoLayout: (VideoLayout) -> Void
    var onToggleVideoWall: () -> Void
    var onToggleCourseware: () -> Void = {}
    var onRequestInteraction: (String) -> Void = { _ in }
    var audioMuted: Bool = true
    var videoMuted: Bool = true
    var onToggleMicrophone: () -> Void = {}
    var onToggleCamera: () -> Void = {}
    var toolbarEntries: [String: ToolbarEntry] = [:]
    var handRaised: Bool = false
    var localScreenSharing: Bool = false
    var onToggleHand: () -> Void = {}
    var onToggleScreenShare: () -> Void = {}
    var showCourseware: Bool = true
    var canEndClass: Bool = false
    var onEnd: () -> Void

    @State private var expanded = false
    private var micOn: Bool { !audioMuted }
    private var camOn: Bool { !videoMuted }
    // 可见性与可用性全部来自 Core 的 interaction_policy。
    private var mic: ToolbarEntry { toolbarEntries.entry("use_microphone") }
    private var camera: ToolbarEntry { toolbarEntries.entry("use_camera") }
    private var raiseHand: ToolbarEntry { toolbarEntries.entry("raise_hand") }
    private var share: ToolbarEntry { toolbarEntries.entry("share_screen") }
    private var courseware: ToolbarEntry { toolbarEntries.entry("operate_courseware") }
    @State private var layoutOpen = false

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    EduColors.surfaceBright.opacity(0),
                    EduColors.surfaceBright.opacity(0.45),
                    EduColors.surfaceBright.opacity(0.88),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .allowsHitTesting(false)

            VStack(spacing: 8) {
                if layoutOpen {
                    LayoutPopupView(selected: videoLayout) {
                        onVideoLayout($0)
                        layoutOpen = false
                    }
                    .transition(.opacity.combined(with: .offset(y: 8)))
                }

                HStack(spacing: EduDimens.stackSm) {
                    CtrlBtnView(
                        icon: expanded ? EduIcons.expandMore : EduIcons.expandLess,
                        label: expanded ? EduI18n.text("controlLess") : EduI18n.text("controlMore")
                    ) {
                        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: EduMotion.floatExpand)) {
                            expanded.toggle()
                            if !expanded { layoutOpen = false }
                        }
                    }
                    if mic.visible {
                        CtrlBtnView(icon: micOn ? EduIcons.mic : EduIcons.micOff, label: restrictedLabel(EduI18n.text("controlMic"), mic), off: !micOn, enabled: !mic.disabled) {
                            onToggleMicrophone()
                        }
                    }
                    if camera.visible {
                        CtrlBtnView(icon: camOn ? EduIcons.videocam : EduIcons.videocamOff, label: restrictedLabel(EduI18n.text("controlCamera"), camera), off: !camOn, enabled: !camera.disabled) {
                            onToggleCamera()
                        }
                    }

                    HStack(spacing: EduDimens.stackSm) {
                        if raiseHand.visible {
                            CtrlBtnView(icon: EduIcons.frontHand, label: EduI18n.text("controlRaiseHand"), active: handRaised, enabled: !raiseHand.disabled) {
                                onToggleHand()
                            }
                        }
                        if share.visible {
                            CtrlBtnView(icon: EduIcons.screenShare, label: restrictedLabel(EduI18n.text("controlShare"), share), active: localScreenSharing, enabled: !share.disabled) {
                                onToggleScreenShare()
                            }
                        }
                        if showCourseware && courseware.visible {
                            CtrlBtnView(
                                icon: EduIcons.slideshow,
                                label: EduI18n.text("controlSlides"),
                                active: coursewareOpen,
                                enabled: !courseware.disabled,
                                action: onToggleCourseware
                            )
                        }
                        CtrlBtnView(icon: EduIcons.viewAgenda, label: EduI18n.text("controlLayout"), active: layoutOpen) {
                            withAnimation(.easeOut(duration: 0.2)) { layoutOpen.toggle() }
                        }
                        CtrlBtnView(icon: EduIcons.gridView, label: "Wall", active: videoWallOpen, action: onToggleVideoWall)
                    }
                    .frame(maxWidth: expanded ? .infinity : 0, alignment: .leading)
                    .opacity(expanded ? 1 : 0)
                    .clipped()
                    .allowsHitTesting(expanded)

                    Rectangle()
                        .fill(EduTint.outlineVariant30)
                        .frame(width: 1, height: 32)
                        .padding(.horizontal, EduDimens.stackSm)

                    CtrlBtnView(icon: EduIcons.callEnd, label: EduI18n.text(canEndClass ? "controlEnd" : "controlLeave"), danger: true, action: onEnd)
                }
                .padding(.horizontal, EduDimens.stackMd)
                .padding(.vertical, EduDimens.stackSm)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(EduColors.surfaceLowest.opacity(0.92)))
                        .overlay(Capsule().stroke(EduTint.outlineVariant45, lineWidth: 1))
                        .eduFloatBarShadow()
                )
            }
            .padding(.bottom, 32)
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: EduMotion.floatExpand), value: expanded)
        .animation(.easeOut(duration: 0.2), value: layoutOpen)
    }
}
