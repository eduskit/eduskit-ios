import SwiftUI
import UIKit

private let panelTools: Set<WhiteboardTool> = [
    .pen, .highlighter, .shape, .text, .eraser, .laser,
]

private let desktopOrder: [WhiteboardTool] = [
    .select, .pen, .highlighter, .shape, .text, .eraser, .laser, .pan,
]

private let mobileOrder: [WhiteboardTool] = [
    .pen, .highlighter, .shape, .text, .eraser, .laser,
]

/// 完整白板工具栏：8 一级工具 + 二级参数面板。
/// - 桌面：面板贴工具列右侧浮层（对齐 Web）。
/// - 移动端：仅工具列；面板由根层 `AnnotationMobilePanelSlot` + PlacementSolver 放置。
struct AnnotationToolbarContentView: View {
    var mobile: Bool = false
    @ObservedObject private var host = WhiteboardHost.shared
    @ObservedObject private var chrome = AnnotationPanelChrome.shared
    @State private var collapsed = false
    @State private var panelOpen = false
    @State private var displayTool: WhiteboardTool = .pen
    @State private var contentFading = false
    @State private var slideDir: CGFloat = 0
    @State private var swapToken = 0
    @State private var toolsHeight: CGFloat = 0
    /// 激活按钮中心相对工具列顶部的 Y（桌面 overlay 定位）
    @State private var anchorY: CGFloat = 40
    @State private var panelHeight: CGFloat = 0
    @State private var toolCenters: [WhiteboardTool: CGFloat] = [:]
    @State private var toolCentersInWindow: [WhiteboardTool: CGFloat] = [:]
    @State private var toolFrameInWindow: CGRect = .null
    @State private var panelFrameInWindow: CGRect = .null
    @State private var swapTask: Task<Void, Never>?
    @State private var lastCloseTick = 0

    private struct ToolItem: Identifiable {
        let id: WhiteboardTool
        let icon: String
    }

    private var tools: [ToolItem] {
        let order = mobile ? mobileOrder : desktopOrder
        return order.map { ToolItem(id: $0, icon: icon(for: $0)) }
    }

    private var showPanel: Bool {
        panelOpen && !collapsed && panelTools.contains(displayTool)
    }

    private var collapseAnim: Animation {
        EduMotion.ease(0.28)
    }

    private var safeFrames: [CGRect] {
        [toolFrameInWindow, panelFrameInWindow].filter { !$0.isNull && !$0.isEmpty }
    }

    private var panelTopOffset: CGFloat {
        let h = panelHeight > 1 ? panelHeight : PlacementSolverDefaults.fallbackPanelHeight
        return max(0, anchorY - h / 2)
    }

    var body: some View {
        Group {
            if mobile {
                toolColumn
                    .fixedSize(horizontal: true, vertical: true)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: AnnoToolFrameKey.self, value: geo.frame(in: .global))
                        }
                    )
                    .onPreferenceChange(AnnoToolFrameKey.self) { frame in
                        toolFrameInWindow = frame
                        syncChrome()
                    }
                    .preference(key: EduFloatBlocksDragKey.self, value: showPanel)
            } else {
                toolColumn
                    .fixedSize(horizontal: true, vertical: true)
                    .overlay(alignment: .topTrailing) {
                        desktopPanelLayer
                    }
                    .background(
                        OutsideTapDismiss(
                            enabled: showPanel,
                            armDelay: AnnotationPanelTokens.outsideTapArmDelay,
                            safeFramesInWindow: safeFrames,
                            onOutside: { closePanel() }
                        )
                    )
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: AnnoToolFrameKey.self, value: geo.frame(in: .global))
                        }
                    )
                    .onPreferenceChange(AnnoToolFrameKey.self) { frame in
                        toolFrameInWindow = frame
                    }
            }
        }
        .onAppear {
            if panelTools.contains(host.tool) {
                displayTool = host.tool
            }
            if mobile {
                lastCloseTick = chrome.closeTick
                syncChrome()
            }
        }
        .onDisappear {
            if mobile {
                AnnotationPanelChrome.shared.reset()
            }
        }
        .onChange(of: chrome.closeTick) { tick in
            guard mobile, tick != lastCloseTick else { return }
            lastCloseTick = tick
            if showPanel { closePanel() }
        }
        .onChange(of: showPanel) { _ in syncChrome() }
        .onChange(of: displayTool) { _ in syncChrome() }
        .onChange(of: contentFading) { _ in syncChrome() }
        .onChange(of: slideDir) { _ in syncChrome() }
        .onChange(of: anchorY) { _ in syncChrome() }
        .onChange(of: collapsed) { _ in syncChrome() }
    }

    /// 移动端：把面板状态同步到根层 Slot。
    private func syncChrome() {
        guard mobile else {
            AnnotationPanelChrome.shared.reset()
            return
        }
        let show = showPanel
        let tool = displayTool
        let fading = contentFading
        let dir = slideDir
        let toolFrame = toolFrameInWindow
        let winY = toolCentersInWindow[displayTool]
            ?? toolCentersInWindow[host.tool]
            ?? (!toolFrameInWindow.isNull && !toolFrameInWindow.isEmpty
                ? toolFrameInWindow.minY + anchorY
                : 0)
        DispatchQueue.main.async {
            let chrome = AnnotationPanelChrome.shared
            chrome.active = true
            chrome.open = show
            chrome.tool = tool
            chrome.fading = fading
            chrome.slideDir = dir
            chrome.toolFrameInWindow = toolFrame
            chrome.anchorYInWindow = winY
        }
    }

    /// 桌面贴工具列浮层：始终挂载，用 opacity 开合。
    @ViewBuilder
    private var desktopPanelLayer: some View {
        panelBody(maxHeight: nil)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                GeometryReader { panelGeo in
                    Color.clear
                        .preference(key: AnnoPanelHeightKey.self, value: panelGeo.size.height)
                        .preference(
                            key: AnnoPanelFrameKey.self,
                            value: showPanel ? panelGeo.frame(in: .global) : .null
                        )
                }
            )
            .onPreferenceChange(AnnoPanelHeightKey.self) { panelHeight = $0 }
            .onPreferenceChange(AnnoPanelFrameKey.self) { panelFrameInWindow = $0 }
            .alignmentGuide(.trailing) { d in
                d[HorizontalAlignment.leading] - (showPanel ? PlacementSolverDefaults.gap : 0)
            }
            .opacity(showPanel ? (contentFading ? 0 : 1) : 0)
            .scaleEffect(
                showPanel ? (contentFading ? 0.98 : 1) : 0.98,
                anchor: .leading
            )
            .offset(y: panelTopOffset + (contentFading ? slideDir * 6 : 0))
            .allowsHitTesting(showPanel && !contentFading)
            .accessibilityHidden(!showPanel)
            .animation(EduMotion.flip(EduMotion.panelOpen), value: showPanel)
            .animation(EduMotion.ease(EduMotion.panelFadeOut), value: contentFading)
            .animation(EduMotion.flip(EduMotion.panelAnchor), value: panelTopOffset)
    }

    private var toolColumn: some View {
        VStack(spacing: 0) {
            if !mobile {
                collapseToggle(icon: collapsed ? EduIcons.expandMore : EduIcons.expandLess)
                Rectangle()
                    .fill(EduTint.outlineVariant20)
                    .frame(height: 1)
                    .padding(.vertical, 4)
            }

            VStack(spacing: 8) {
                ForEach(tools) { item in
                    annoBtn(icon: item.icon, active: host.tool == item.id) {
                        selectTool(item.id)
                    }
                    .background(
                        GeometryReader { geo in
                            let localMid = geo.frame(in: .named("annoStack")).midY
                            let globalMid = geo.frame(in: .global).midY
                            Color.clear.preference(
                                key: AnnoToolCenterKey.self,
                                value: [item.id: AnnoToolCenter(localY: localMid, windowY: globalMid)]
                            )
                        }
                    )
                }
            }
            .padding(.bottom, mobile ? 8 : 0)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: AnnoToolsHeightKey.self, value: geo.size.height)
                }
            )
            .onPreferenceChange(AnnoToolsHeightKey.self) { height in
                if height > 1 { toolsHeight = height }
            }
            .onPreferenceChange(AnnoToolCenterKey.self) { centers in
                for (tool, center) in centers {
                    toolCenters[tool] = center.localY
                    toolCentersInWindow[tool] = center.windowY
                }
                if let y = toolCenters[host.tool] ?? toolCenters[displayTool] {
                    withAnimation(EduMotion.flip(EduMotion.panelAnchor)) {
                        anchorY = y
                    }
                }
                syncChrome()
            }
            .frame(height: collapsed ? 0 : (toolsHeight > 0 ? toolsHeight : nil), alignment: .top)
            .opacity(collapsed ? 0 : 1)
            .clipped()
            .allowsHitTesting(!collapsed)

            if mobile {
                collapseToggle(icon: collapsed ? EduIcons.expandLess : EduIcons.expandMore)
            }
        }
        // 对齐 Web `.edu-anno__stack`：桌面 8×6，移动端 6
        .padding(mobile ? EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
                        : EdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6))
        .coordinateSpace(name: "annoStack")
        .background {
            if mobile {
                Capsule()
                    .fill(Color.white)
                    .overlay(Capsule().stroke(EduColors.surfaceLow, lineWidth: 1))
                    .eduShadow(.level3)
            } else {
                RoundedRectangle(cornerRadius: EduDimens.radiusXl, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: EduDimens.radiusXl, style: .continuous)
                            .stroke(EduColors.surfaceLow, lineWidth: 1)
                    )
                    .eduShadow(.soft)
            }
        }
    }

    @ViewBuilder
    private func panelBody(maxHeight: CGFloat?) -> some View {
        switch displayTool {
        case .pen: PenPanelView(maxHeight: maxHeight)
        case .highlighter: HighlighterPanelView(maxHeight: maxHeight)
        case .shape: ShapePanelView(maxHeight: maxHeight)
        case .text: TextPanelView(maxHeight: maxHeight)
        case .eraser: EraserPanelView(maxHeight: maxHeight)
        case .laser: LaserPanelView(maxHeight: maxHeight)
        default: EmptyView()
        }
    }

    private func icon(for tool: WhiteboardTool) -> String {
        switch tool {
        case .select: return EduIcons.nearMe
        case .pen: return EduIcons.edit
        case .highlighter: return EduIcons.highlight
        case .shape: return EduIcons.formatShapes
        case .text: return EduIcons.title
        case .eraser: return EduIcons.inkEraser
        case .laser: return EduIcons.gesture
        case .pan: return EduIcons.panTool
        }
    }

    private func openPanel(_ tool: WhiteboardTool) {
        swapToken += 1
        swapTask?.cancel()
        contentFading = false
        slideDir = 0
        displayTool = tool
        if let y = toolCenters[tool] { anchorY = y }
        withAnimation(EduMotion.flip(EduMotion.panelOpen)) {
            panelOpen = true
        }
        syncChrome()
    }

    private func closePanel() {
        swapToken += 1
        swapTask?.cancel()
        contentFading = false
        slideDir = 0
        panelFrameInWindow = .null
        withAnimation(EduMotion.ease(EduMotion.panelCloseFade)) {
            panelOpen = false
        }
        syncChrome()
    }

    private func swapPanel(_ tool: WhiteboardTool, from: WhiteboardTool) {
        if tool == displayTool && showPanel {
            if let y = toolCenters[tool] {
                withAnimation(EduMotion.flip(EduMotion.panelAnchor)) { anchorY = y }
            }
            syncChrome()
            return
        }
        let token = swapToken + 1
        swapToken = token
        swapTask?.cancel()
        let order = mobile ? mobileOrder : desktopOrder
        let a = order.firstIndex(of: from) ?? 0
        let b = order.firstIndex(of: tool) ?? 0
        slideDir = b >= a ? 1 : -1

        swapTask = Task { @MainActor in
            withAnimation(EduMotion.ease(EduMotion.panelFadeOut)) {
                contentFading = true
            }
            syncChrome()
            try? await Task.sleep(nanoseconds: UInt64(EduMotion.panelFadeOut * 1_000_000_000))
            guard !Task.isCancelled, token == swapToken else { return }

            displayTool = tool
            if let y = toolCenters[tool] {
                withAnimation(EduMotion.flip(EduMotion.panelAnchor)) { anchorY = y }
            }
            syncChrome()
            try? await Task.sleep(nanoseconds: UInt64(EduMotion.panelSwapMorph * 1_000_000_000))
            guard !Task.isCancelled, token == swapToken else { return }

            withAnimation(EduMotion.ease(EduMotion.panelFadeIn)) {
                contentFading = false
            }
            syncChrome()
            try? await Task.sleep(nanoseconds: UInt64(EduMotion.panelFadeIn * 1_000_000_000))
            guard !Task.isCancelled, token == swapToken else { return }
            slideDir = 0
            syncChrome()
        }
    }

    private func selectTool(_ tool: WhiteboardTool) {
        if let y = toolCenters[tool] {
            withAnimation(EduMotion.flip(EduMotion.panelAnchor)) { anchorY = y }
        }
        let prev = host.tool
        let wasOpen = showPanel
        if tool == prev {
            if panelTools.contains(tool) {
                if wasOpen { closePanel() } else { openPanel(tool) }
            }
        } else {
            host.setTool(tool)
            if panelTools.contains(tool) {
                if wasOpen && panelTools.contains(prev) {
                    panelOpen = true
                    displayTool = tool
                    swapPanel(tool, from: prev)
                } else {
                    openPanel(tool)
                }
            } else {
                closePanel()
            }
        }
    }

    private func collapseToggle(icon: String) -> some View {
        Button {
            withAnimation(collapseAnim) {
                collapsed.toggle()
                if collapsed { closePanel() }
            }
        } label: {
            EduIcon(icon, size: mobile ? 18 : 20, tint: EduColors.onSurfaceVariant)
                .frame(width: mobile ? 32 : 36, height: mobile ? 32 : 36)
        }
        .buttonStyle(.plain)
    }

    private func annoBtn(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        let size: CGFloat = mobile ? 32 : 36
        return Button(action: action) {
            EduIcon(
                icon,
                size: mobile ? 18 : 20,
                tint: active ? EduColors.primary : EduColors.onSurfaceVariant
            )
            .frame(width: size, height: size)
            .background(active ? EduColors.surfaceContainer : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(EduPressButtonStyle())
    }
}

/// 工具栏 + GlobalOps + SelectContextBar 堆叠入口。
/// 桌面端对齐 Web：GlobalOps / SelectContext 绝对定位，不撑宽工具列（避免整组显宽后看起来偏右）。
struct AnnotationToolbarStackView: View {
    var mobile: Bool = false
    var showGlobalOps: Bool = true
    @ObservedObject private var host = WhiteboardHost.shared

    var body: some View {
        if mobile {
            VStack(alignment: .leading, spacing: 8) {
                AnnotationToolbarContentView(mobile: true)
                if showGlobalOps {
                    GlobalOpsView(compact: true)
                }
            }
            .fixedSize(horizontal: true, vertical: true)
        } else {
            AnnotationToolbarContentView(mobile: false)
                .overlay(alignment: .topLeading) {
                    if !host.selection.isEmpty {
                        SelectContextBarView()
                            .fixedSize()
                            .alignmentGuide(.top) { $0[.bottom] + 12 }
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if showGlobalOps {
                        GlobalOpsView(compact: false)
                            .fixedSize()
                            .alignmentGuide(.bottom) { $0[.top] - 12 }
                    }
                }
                .fixedSize(horizontal: true, vertical: true)
        }
    }
}

private struct AnnoToolCenter: Equatable {
    var localY: CGFloat
    var windowY: CGFloat
}

private struct AnnoToolsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > value { value = next }
    }
}

private struct AnnoToolCenterKey: PreferenceKey {
    static var defaultValue: [WhiteboardTool: AnnoToolCenter] = [:]
    static func reduce(value: inout [WhiteboardTool: AnnoToolCenter], nextValue: () -> [WhiteboardTool: AnnoToolCenter]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct AnnoPanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct AnnoToolFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct AnnoPanelFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
