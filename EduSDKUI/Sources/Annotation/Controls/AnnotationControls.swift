import SwiftUI

struct ColorSwatchView: View {
    let color: String
    let active: Bool
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(AnnotationDefaults.color(from: color))
                .frame(width: 20, height: 20)
                .overlay(
                    Circle().stroke(
                        active ? EduColors.primary : EduColors.outlineVariant.opacity(0.6),
                        lineWidth: 1.5
                    )
                )
                .overlay {
                    if active {
                        Circle().stroke(EduTint.primaryRing22, lineWidth: 2)
                    }
                }
                .scaleEffect(pressed ? 1.08 : 1)
                .animation(.easeOut(duration: 0.12), value: pressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}

struct ColorPickerRowView: View {
    let value: String
    var swatches: [String] = AnnotationDefaults.swatches
    var allowNone: Bool = false
    var onSelectNone: (() -> Void)? = nil
    let onChange: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if allowNone {
                let noneActive = value.isEmpty
                Button {
                    onSelectNone?()
                } label: {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle().stroke(
                                noneActive ? EduColors.primary : EduColors.outlineVariant,
                                lineWidth: 1.5
                            )
                        )
                        .overlay {
                            if noneActive {
                                Circle().stroke(EduTint.primaryRing22, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            ForEach(swatches, id: \.self) { c in
                ColorSwatchView(
                    color: c,
                    active: c.caseInsensitiveCompare(value) == .orderedSame,
                    action: { onChange(c) }
                )
            }
        }
    }
}

struct EduSliderView: View {
    let value: Int
    var minValue: Int = 0
    var maxValue: Int = 100
    var presets: [Int] = []
    var enabled: Bool = true
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { if enabled { onChange(Int($0.rounded())) } }
                ),
                in: Double(minValue)...Double(maxValue),
                step: 1
            )
            .tint(EduColors.primary)
            .disabled(!enabled)

            if !presets.isEmpty {
                HStack(spacing: 4) {
                    ForEach(presets, id: \.self) { p in
                        let active = value == p
                        Text("\(p)")
                            .font(EduFont.sans(11, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? EduColors.primary : EduColors.onSurfaceVariant)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(active ? EduColors.primary.opacity(0.12) : Color.clear)
                            )
                            .overlay(
                                Capsule().stroke(
                                    active ? EduColors.primary.opacity(0.45) : EduColors.outlineVariant.opacity(0.45),
                                    lineWidth: 1
                                )
                            )
                            .onTapGesture { if enabled { onChange(p) } }
                    }
                }
            }
        }
        .opacity(enabled ? 1 : 0.45)
    }
}

struct SegmentOption: Identifiable {
    let id: Int
    let label: String
    init(_ value: Int, _ label: String) { self.id = value; self.label = label }
}

struct SegmentedView: View {
    let value: Int
    let options: [SegmentOption]
    var enabled: Bool = true
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { opt in
                let active = opt.id == value
                Text(opt.label)
                    .font(EduFont.sans(11, weight: active ? .semibold : .medium))
                    .foregroundStyle(
                        !enabled ? EduColors.onSurfaceVariant.opacity(0.35)
                        : active ? EduColors.primary : EduColors.onSurfaceVariant
                    )
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                    .background {
                        if active && enabled {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(EduColors.surfaceLowest)
                                .shadow(color: EduTint.chipShadow, radius: 1.5, y: 1)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if enabled { onChange(opt.id) } }
            }
        }
        .padding(2)
        .background(EduColors.surfaceLow)
        .overlay(
            RoundedRectangle(cornerRadius: EduDimens.radiusXl, style: .continuous)
                .stroke(EduTint.outlineVariant45, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: EduDimens.radiusXl, style: .continuous))
        .opacity(enabled ? 1 : 0.45)
    }
}

/// 紧凑开关 34×20 / thumb 16 — 对齐 Web `.edu-switch`
struct ToggleSwitchView: View {
    let checked: Bool
    var enabled: Bool = true
    let onChange: (Bool) -> Void

    var body: some View {
        Button {
            if enabled { onChange(!checked) }
        } label: {
            ZStack(alignment: checked ? .trailing : .leading) {
                Capsule()
                    .fill(checked ? EduColors.primary : EduColors.outlineVariant.opacity(0.6))
                    .frame(width: 34, height: 20)
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
                    .padding(2)
            }
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.18), value: checked)
        .disabled(!enabled)
    }
}

enum PreviewKind { case pen, highlighter, eraser, laser }

struct ToolPreviewView: View {
    let kind: PreviewKind
    var color: String = "#000000"
    var thin: Int = 50
    var size: Int = 50

    var body: some View {
        let diameter: CGFloat = {
            switch kind {
            case .pen: return AnnotationDefaults.penDiameter(thin)
            case .highlighter: return AnnotationDefaults.highlighterDiameter(thin)
            case .eraser: return AnnotationDefaults.eraserDiameter(size)
            case .laser: return AnnotationDefaults.laserDiameter(size)
            }
        }()
        let fill = AnnotationDefaults.color(from: color)
        let alpha: Double = kind == .highlighter ? AnnotationDefaults.highlighterAlpha : 1
        let hollow = kind == .eraser
        let halo = kind == .laser ? AnnotationDefaults.laserHalo : 0
        let d = min(diameter, 28)

        ZStack {
            if halo > 0 {
                Circle()
                    .fill(fill.opacity(0.32))
                    .frame(width: d * halo, height: d * halo)
                    .blur(radius: 3)
            }
            if hollow {
                Circle()
                    .stroke(EduColors.onSurfaceVariant, lineWidth: 1.5)
                    .frame(width: d, height: d)
            } else {
                Circle()
                    .fill(fill.opacity(alpha))
                    .frame(width: d, height: d)
            }
        }
        .frame(width: 32, height: 32)
        .animation(EduMotion.ease(EduMotion.panelPreview), value: d)
    }
}

struct PanelShellView<Content: View>: View {
    var maxHeight: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if let maxHeight {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        content()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(width: 260, alignment: .leading)
                }
                .frame(width: 260, alignment: .topLeading)
                .frame(maxHeight: maxHeight, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(width: 260, alignment: .leading)
            }
        }
        .background(EduColors.surfaceLowest.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: EduDimens.radiusXl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EduDimens.radiusXl, style: .continuous)
                .stroke(EduColors.surfaceLow, lineWidth: 1)
        )
        .eduPanelShadow()
    }
}

struct PanelHeaderView: View {
    let title: String
    var preview: AnyView? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(EduFont.panelTitle)
                    .foregroundStyle(EduColors.onSurface)
                Spacer()
                if let preview { preview }
            }
            .padding(.bottom, 6)
            Rectangle()
                .fill(EduTint.outlineVariant20)
                .frame(height: 1)
        }
    }
}

struct PanelSectionView<Content: View>: View {
    let label: String
    var disabled: Bool = false
    var trailing: AnyView? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label.uppercased())
                    .font(EduFont.panelSection)
                    .tracking(0.22)
                    .foregroundStyle(
                        disabled ? EduColors.outlineVariant : EduColors.onSurfaceVariant
                    )
                Spacer()
                if let trailing { trailing }
            }
            content()
                .allowsHitTesting(!disabled)
        }
        .opacity(disabled ? 0.5 : 1)
    }
}

struct DangerActionButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(EduFont.sans(12, weight: .medium))
                .foregroundStyle(EduColors.error)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(EduTint.errorTint8)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(EduPressButtonStyle())
    }
}

struct SubToolTrack<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 4) {
            content()
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EduColors.surfaceLow)
        .clipShape(RoundedRectangle(cornerRadius: EduDimens.radiusXl, style: .continuous))
    }
}
