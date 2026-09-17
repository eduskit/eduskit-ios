import SwiftUI

struct PenPanelView: View {
    var maxHeight: CGFloat? = nil
    @ObservedObject private var host = WhiteboardHost.shared

    var body: some View {
        let pen = host.pen
        let taperDisabled = pen.lineStyle != WhiteboardLineStyle.solid.rawValue
        let autoFitDisabled = !pen.magicPen

        PanelShellView(maxHeight: maxHeight) {
            PanelHeaderView(title: EduI18n.text("panelPenTitle"), preview: AnyView(
                ToolPreviewView(kind: .pen, color: pen.color, thin: pen.thin)
            ))
            PanelSectionView(label: EduI18n.text("panelSectionColor")) {
                ColorPickerRowView(value: pen.color) {
                    host.updatePen(PenPatch(color: $0))
                }
            }
            PanelSectionView(label: EduI18n.text("panelSectionSize")) {
                EduSliderView(value: pen.thin, presets: [14, 30, 60, 90]) {
                    host.updatePen(PenPatch(thin: $0))
                }
            }
            PanelSectionView(label: EduI18n.text("annotationTaperResponse")) {
                SegmentedView(
                    value: pen.thinMode,
                    options: [SegmentOption(0, EduI18n.text("panelSegThinFixed")), SegmentOption(1, EduI18n.text("panelSegThinPressure"))]
                ) { host.updatePen(PenPatch(thinMode: $0)) }
            }
            PanelSectionView(label: EduI18n.text("panelSectionLineStyle")) {
                SegmentedView(
                    value: pen.lineStyle,
                    options: [SegmentOption(0, EduI18n.text("annotationSegmentSolid")), SegmentOption(1, EduI18n.text("annotationSegmentDash")), SegmentOption(2, EduI18n.text("annotationSegmentDot"))]
                ) { host.updatePen(PenPatch(lineStyle: $0)) }
            }
            PanelSectionView(
                label: EduI18n.text("panelToggleTaper"),
                disabled: taperDisabled,
                trailing: AnyView(
                    ToggleSwitchView(checked: pen.taper && !taperDisabled, enabled: !taperDisabled) {
                        host.updatePen(PenPatch(taper: $0))
                    }
                )
            ) { EmptyView() }
            PanelSectionView(
                label: EduI18n.text("panelToggleMagicPen"),
                trailing: AnyView(
                    ToggleSwitchView(checked: pen.magicPen) {
                        host.updatePen(PenPatch(magicPen: $0))
                    }
                )
            ) { EmptyView() }
            PanelSectionView(label: EduI18n.text("annotationRecognitionMode"), disabled: autoFitDisabled) {
                SegmentedView(
                    value: pen.autoFittingMode,
                    options: [SegmentOption(0, EduI18n.text("panelSegFitSmooth")), SegmentOption(1, EduI18n.text("panelSegFitDetect"))],
                    enabled: !autoFitDisabled
                ) { host.updatePen(PenPatch(autoFittingMode: $0)) }
            }
        }
    }
}

struct HighlighterPanelView: View {
    var maxHeight: CGFloat? = nil
    @ObservedObject private var host = WhiteboardHost.shared

    var body: some View {
        PanelShellView(maxHeight: maxHeight) {
            PanelHeaderView(title: EduI18n.text("panelHighlighterTitle"), preview: AnyView(
                ToolPreviewView(kind: .highlighter, color: host.highlighter.color, thin: host.pen.thin)
            ))
            PanelSectionView(label: EduI18n.text("panelSectionColor")) {
                ColorPickerRowView(
                    value: host.highlighter.color,
                    swatches: AnnotationDefaults.highlighterSwatches
                ) { host.updateHighlighter(HighlighterPatch(color: $0)) }
            }
            Text(EduI18n.text("panelHighlighterHint"))
                .font(.system(size: 11))
                .foregroundStyle(EduColors.onSurfaceVariant)
        }
    }
}

struct ShapePanelView: View {
    var maxHeight: CGFloat? = nil
    @ObservedObject private var host = WhiteboardHost.shared

    private struct Sub: Identifiable {
        let id: ShapeSubTool
        let icon: String
        let label: String
    }

    private let subs: [Sub] = [
        Sub(id: .rect, icon: EduIcons.checkBoxOutlineBlank, label: EduI18n.text("panelShapeRect")),
        Sub(id: .rectSolid, icon: EduIcons.rectangle, label: EduI18n.text("annotationRectSolid")),
        Sub(id: .oval, icon: EduIcons.circle, label: EduI18n.text("panelShapeOval")),
        Sub(id: .ovalSolid, icon: EduIcons.brightness1, label: EduI18n.text("annotationOvalSolid")),
        Sub(id: .line, icon: EduIcons.horizontalRule, label: EduI18n.text("panelShapeLine")),
        Sub(id: .arrow, icon: EduIcons.arrowRightAlt, label: EduI18n.text("panelShapeArrow")),
    ]

    var body: some View {
        let shape = host.shape
        let isSolid = shape.subTool == .rectSolid || shape.subTool == .ovalSolid
        let isOval = shape.subTool == .oval || shape.subTool == .ovalSolid
        let fillDisabled = !shape.fillEnabled

        PanelShellView(maxHeight: maxHeight) {
                    PanelHeaderView(title: EduI18n.text("panelShapeTitle"))
                    SubToolTrack {
                        ForEach(subs) { s in
                            let active = shape.subTool == s.id
                            Button { host.setShapeSubTool(s.id) } label: {
                                EduIcon(
                                    s.icon,
                                    size: 18,
                                    tint: active ? EduColors.primary : EduColors.onSurfaceVariant
                                )
                                .frame(width: 36, height: 36)
                                .background {
                                    if active {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(EduColors.surfaceLowest)
                                            .shadow(color: EduTint.chipShadow, radius: 1.5, y: 1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    PanelSectionView(label: EduI18n.text("annotationStrokeColor")) {
                        ColorPickerRowView(value: shape.color) {
                            host.updateShape(ShapePatch(color: $0))
                        }
                    }
                    PanelSectionView(label: EduI18n.text("annotationStrokeWidth")) {
                        EduSliderView(value: shape.thin) {
                            host.updateShape(ShapePatch(thin: $0))
                        }
                    }
                    PanelSectionView(label: EduI18n.text("panelSectionLineStyle")) {
                        SegmentedView(
                            value: shape.lineStyle,
                            options: [SegmentOption(0, EduI18n.text("annotationSegmentSolid")), SegmentOption(1, EduI18n.text("annotationSegmentDash")), SegmentOption(2, EduI18n.text("annotationSegmentDot"))]
                        ) { host.updateShape(ShapePatch(lineStyle: $0)) }
                    }
                    PanelSectionView(
                        label: isSolid ? EduI18n.text("annotationFillOn") : EduI18n.text("annotationFillEnable"),
                        trailing: AnyView(
                            ToggleSwitchView(checked: shape.fillEnabled, enabled: !isSolid) {
                                host.updateShape(ShapePatch(fillEnabled: $0))
                            }
                        )
                    ) { EmptyView() }
                    PanelSectionView(label: EduI18n.text("annotationFillColor"), disabled: fillDisabled) {
                        ColorPickerRowView(
                            value: shape.fillColor ?? "",
                            allowNone: true,
                            onSelectNone: { host.updateShape(ShapePatch(fillColorCleared: true)) }
                        ) { host.updateShape(ShapePatch(fillColor: $0)) }
                    }
                    PanelSectionView(label: EduI18n.text("annotationFillPattern"), disabled: fillDisabled) {
                        SegmentedView(
                            value: shape.fillStyle,
                            options: [
                                SegmentOption(0, EduI18n.text("annotationPatternHatch")), SegmentOption(1, EduI18n.text("annotationPatternCross")),
                                SegmentOption(2, EduI18n.text("annotationPatternSolid")), SegmentOption(3, EduI18n.text("annotationPatternZigzag")),
                            ],
                            enabled: !fillDisabled
                        ) { host.updateShape(ShapePatch(fillStyle: $0)) }
                    }
                    PanelSectionView(label: EduI18n.text("panelSectionHandDrawn")) {
                        SegmentedView(
                            value: shape.roughness,
                            options: [SegmentOption(0, EduI18n.text("panelSegRoughNeat")), SegmentOption(1, EduI18n.text("panelSegRoughNatural")), SegmentOption(2, EduI18n.text("panelSegRoughWild"))]
                        ) { host.updateShape(ShapePatch(roughness: $0)) }
                    }
                    PanelSectionView(label: EduI18n.text("panelSegRoundRound")) {
                        SegmentedView(
                            value: shape.roundness,
                            options: [SegmentOption(0, EduI18n.text("panelSegRoundSharp")), SegmentOption(1, EduI18n.text("panelSegRoundRound"))]
                        ) { host.updateShape(ShapePatch(roundness: $0)) }
                    }
                    PanelSectionView(
                        label: EduI18n.text("panelToggleArrowEnd"),
                        trailing: AnyView(
                            ToggleSwitchView(checked: shape.arrowEnd) {
                                host.updateShape(ShapePatch(arrowEnd: $0))
                            }
                        )
                    ) { EmptyView() }
                    if isOval {
                        PanelSectionView(label: EduI18n.text("annotationOvalDrawing")) {
                            SegmentedView(
                                value: shape.ovalDrawMode,
                                options: [SegmentOption(0, EduI18n.text("panelSegOvalStart")), SegmentOption(1, EduI18n.text("panelSegOvalCenter"))]
                            ) { host.updateShape(ShapePatch(ovalDrawMode: $0)) }
                        }
                    }
        }
    }
}

struct TextPanelView: View {
    var maxHeight: CGFloat? = nil
    @ObservedObject private var host = WhiteboardHost.shared

    var body: some View {
        let text = host.text
        let bold = (text.style & 1) != 0
        let italic = (text.style & 2) != 0

        PanelShellView(maxHeight: maxHeight) {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeaderView(title: EduI18n.text("panelTextTitle"))
                PanelSectionView(label: EduI18n.text("panelSectionColor")) {
                    ColorPickerRowView(value: text.color) {
                        host.updateText(TextPatch(color: $0))
                    }
                }
                PanelSectionView(label: EduI18n.text("panelSectionFont")) {
                    Picker(
                        "",
                        selection: Binding(
                            get: { text.fontFamily },
                            set: { host.updateText(TextPatch(fontFamily: $0)) }
                        )
                    ) {
                        ForEach(AnnotationDefaults.textFonts, id: \.self) { font in
                            Text(font).tag(font)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(EduColors.surfaceLowest)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(EduColors.outlineVariant.opacity(0.45), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                PanelSectionView(label: EduI18n.text("panelSectionFontSize")) {
                    EduSliderView(
                        value: max(12, min(640, text.size)),
                        minValue: 12,
                        maxValue: 640,
                        presets: [160, 320, 480]
                    ) {
                        let snapped = ($0 / 4) * 4
                        host.updateText(TextPatch(size: max(12, min(640, snapped))))
                    }
                    Text(EduI18n.text("annotationCurrentSize", ["size": text.size]))
                        .font(.system(size: 11))
                        .foregroundStyle(EduColors.onSurfaceVariant)
                }
                PanelSectionView(label: EduI18n.text("panelSectionTextStyle")) {
                    HStack(spacing: 8) {
                        styleChip("B", active: bold) {
                            let next = bold ? (text.style & ~1) : (text.style | 1)
                            host.updateText(TextPatch(style: next))
                        }
                        styleChip("I", active: italic) {
                            let next = italic ? (text.style & ~2) : (text.style | 2)
                            host.updateText(TextPatch(style: next))
                        }
                    }
                }
                PanelSectionView(label: EduI18n.text("annotationLineHeight")) {
                    EduSliderView(
                        value: Int(((text.lineHeight - 0.5) / 1.5 * 100).rounded())
                    ) {
                        let lh = 0.5 + Float($0) / 100 * 1.5
                        host.updateText(TextPatch(lineHeight: lh))
                    }
                }
            }
        }
    }

    private func styleChip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(active ? EduColors.primary : EduColors.onSurfaceVariant)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(active ? EduColors.surfaceContainer : EduColors.surfaceLow)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(EduPressButtonStyle())
    }
}

struct EraserPanelView: View {
    var maxHeight: CGFloat? = nil
    @ObservedObject private var host = WhiteboardHost.shared

    var body: some View {
        PanelShellView(maxHeight: maxHeight) {
            PanelHeaderView(title: EduI18n.text("panelEraserTitle"), preview: AnyView(
                ToolPreviewView(kind: .eraser, size: host.eraser.size)
            ))
            PanelSectionView(label: EduI18n.text("annotationSize")) {
                EduSliderView(value: host.eraser.size, presets: [30, 50, 80]) {
                    host.updateEraser(EraserPatch(size: $0))
                }
            }
            PanelSectionView(label: EduI18n.text("annotationEraseMode")) {
                SegmentedView(
                    value: host.eraser.mode,
                    options: [
                        SegmentOption(EraserMode.whole.rawValue, EduI18n.text("annotationEraseWhole")),
                        SegmentOption(EraserMode.piece.rawValue, EduI18n.text("annotationErasePiece")),
                    ]
                ) { host.updateEraser(EraserPatch(mode: $0)) }
            }
            DangerActionButton(label: EduI18n.text("panelClearBoard")) {
                host.clear()
            }
        }
    }
}

struct LaserPanelView: View {
    var maxHeight: CGFloat? = nil
    @ObservedObject private var host = WhiteboardHost.shared

    var body: some View {
        PanelShellView(maxHeight: maxHeight) {
            PanelHeaderView(title: EduI18n.text("panelLaserTitle"), preview: AnyView(
                ToolPreviewView(kind: .laser, color: "#ff2757", size: host.laser.size)
            ))
            PanelSectionView(label: EduI18n.text("annotationLaserSize")) {
                EduSliderView(value: host.laser.size) {
                    host.updateLaser(LaserPatch(size: $0))
                }
            }
        }
    }
}
