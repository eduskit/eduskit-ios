import SwiftUI

/// 移动端配置面板协调器：工具列在 `EduDraggableFloat` 内，面板提到布局根层。
final class AnnotationPanelChrome: ObservableObject {
    static let shared = AnnotationPanelChrome()

    @Published var active = false
    @Published var open = false
    @Published var tool: WhiteboardTool = .pen
    @Published var fading = false
    @Published var slideDir: CGFloat = 0
    @Published var toolFrameInWindow: CGRect = .null
    @Published var panelFrameInWindow: CGRect = .null
    @Published var anchorYInWindow: CGFloat = 0
    /// 外点关闭时递增；工具栏 `onChange` 响应（避免 SwiftUI View 闭包捕获失效）。
    @Published var closeTick: Int = 0

    func reset() {
        active = false
        open = false
        fading = false
        slideDir = 0
        toolFrameInWindow = .null
        panelFrameInWindow = .null
        anchorYInWindow = 0
        closeTick = 0
    }

    func requestClose() {
        closeTick += 1
    }
}

/// 视口级面板宿主：`chrome.active` 时始终挂载，用 opacity 开合；PlacementSolver 定位。
/// 关闭时整层 `allowsHitTesting(false)` 穿透；打开时接住面板交互（外点由 OutsideTap 关）。
struct AnnotationMobilePanelSlot: View {
    @ObservedObject private var chrome = AnnotationPanelChrome.shared
    @State private var panelSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let slotGlobal = geo.frame(in: .global)
            let place = resolvedPlacement(slotGlobal: slotGlobal)
            let side = place?.side ?? .left
            let maxH = place?.maxHeight
                ?? max(
                    PlacementSolverDefaults.minPanelHeight,
                    slotGlobal.height - PlacementSolverDefaults.edgePad * 2
                )

            ZStack(alignment: .topLeading) {
                if chrome.active {
                    panelBody(maxHeight: maxH)
                        .background(
                            GeometryReader { panelGeo in
                                Color.clear.preference(
                                    key: AnnoMobilePanelSizeKey.self,
                                    value: panelGeo.size
                                )
                            }
                        )
                        .opacity(chrome.open ? (chrome.fading ? 0 : 1) : 0)
                        .scaleEffect(
                            chrome.open ? (chrome.fading ? 0.98 : 1) : 0.98,
                            anchor: scaleAnchor(for: side)
                        )
                        .offset(panelOffset(place: place, slotGlobal: slotGlobal, panelHeight: maxH))
                        .allowsHitTesting(chrome.open && !chrome.fading)
                        .accessibilityHidden(!chrome.open)
                        .animation(EduMotion.flip(EduMotion.panelOpen), value: chrome.open)
                        .animation(EduMotion.ease(EduMotion.panelFadeOut), value: chrome.fading)
                        .animation(EduMotion.flip(EduMotion.panelAnchor), value: chrome.toolFrameInWindow)
                        .background(
                            GeometryReader { panelGeo in
                                Color.clear.preference(
                                    key: AnnoMobilePanelFrameKey.self,
                                    value: chrome.open ? panelGeo.frame(in: .global) : .null
                                )
                            }
                        )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .allowsHitTesting(chrome.open && !chrome.fading)
        .onPreferenceChange(AnnoMobilePanelSizeKey.self) { panelSize = $0 }
        .onPreferenceChange(AnnoMobilePanelFrameKey.self) { frame in
            DispatchQueue.main.async {
                AnnotationPanelChrome.shared.panelFrameInWindow = frame
            }
        }
        .background(
            OutsideTapDismiss(
                enabled: chrome.open,
                armDelay: AnnotationPanelTokens.outsideTapArmDelay,
                safeFramesInWindow: [
                    chrome.toolFrameInWindow,
                    chrome.panelFrameInWindow,
                ].filter { !$0.isNull && !$0.isEmpty },
                onOutside: { AnnotationPanelChrome.shared.requestClose() }
            )
        )
    }

    private func resolvedPlacement(slotGlobal: CGRect) -> PanelPlacement? {
        guard chrome.open else { return nil }
        let tool = chrome.toolFrameInWindow
        guard !tool.isNull, !tool.isEmpty, tool.width > 1 else { return nil }
        guard slotGlobal.width > 48, slotGlobal.height > 48 else { return nil }
        let safe = insetRect(slotGlobal, pad: PlacementSolverDefaults.edgePad)
        guard !safe.isNull else { return nil }
        let intrinsicH = panelSize.height > 1
            ? panelSize.height
            : PlacementSolverDefaults.fallbackPanelHeight
        let anchorY = chrome.anchorYInWindow > 1 ? chrome.anchorYInWindow : tool.midY
        return resolvePanelPlacement(
            toolFrame: tool,
            panelWidth: PlacementSolverDefaults.defaultPanelWidth,
            panelHeight: intrinsicH,
            safeRect: safe,
            anchorY: anchorY
        )
    }

    private func panelOffset(
        place: PanelPlacement?,
        slotGlobal: CGRect,
        panelHeight: CGFloat
    ) -> CGSize {
        let fadeNudge = chrome.fading ? chrome.slideDir * 6 : 0
        let closedNudge: CGFloat = chrome.open ? 0 : -PlacementSolverDefaults.gap

        if let place {
            return CGSize(
                width: place.origin.x - slotGlobal.minX + closedNudge,
                height: place.origin.y - slotGlobal.minY + fadeNudge
            )
        }

        let tool = chrome.toolFrameInWindow
        let h = panelSize.height > 1 ? panelSize.height : panelHeight
        let w = PlacementSolverDefaults.defaultPanelWidth
        let gap = PlacementSolverDefaults.gap
        let pad = PlacementSolverDefaults.edgePad

        if !tool.isNull, !tool.isEmpty, slotGlobal.width > 1 {
            var x = tool.maxX + gap
            if x + w > slotGlobal.maxX - pad {
                x = tool.minX - gap - w
            }
            x = min(max(x, slotGlobal.minX + pad), slotGlobal.maxX - w - pad)
            var y = (chrome.anchorYInWindow > 1 ? chrome.anchorYInWindow : tool.midY) - h / 2
            y = min(max(y, slotGlobal.minY + pad), slotGlobal.maxY - h - pad)
            return CGSize(
                width: x - slotGlobal.minX + closedNudge,
                height: y - slotGlobal.minY + fadeNudge
            )
        }

        return CGSize(
            width: pad + closedNudge,
            height: max(pad, slotGlobal.height - h - AnnotationPanelTokens.fallbackBottomReserve) + fadeNudge
        )
    }

    private func scaleAnchor(for side: PanelSide) -> UnitPoint {
        switch side {
        case .right: return .leading
        case .left: return .trailing
        case .above: return .bottom
        case .below: return .top
        }
    }

    @ViewBuilder
    private func panelBody(maxHeight: CGFloat) -> some View {
        switch chrome.tool {
        case .pen: PenPanelView(maxHeight: maxHeight)
        case .highlighter: HighlighterPanelView(maxHeight: maxHeight)
        case .shape: ShapePanelView(maxHeight: maxHeight)
        case .text: TextPanelView(maxHeight: maxHeight)
        case .eraser: EraserPanelView(maxHeight: maxHeight)
        case .laser: LaserPanelView(maxHeight: maxHeight)
        default: EmptyView()
        }
    }
}

enum AnnotationPanelTokens {
    static let outsideTapArmDelay: TimeInterval = 0.12
    static let fallbackBottomReserve: CGFloat = 88
    static let mobileMaxHeight: CGFloat = 420
}

private struct AnnoMobilePanelFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct AnnoMobilePanelSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
