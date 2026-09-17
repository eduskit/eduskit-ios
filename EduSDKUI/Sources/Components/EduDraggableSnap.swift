import SwiftUI

public enum SnapAnchor {
    case topEnd, topStart, bottomEnd, bottomStart
    case leftCenter, rightCenter
}

/// Independently positioned float: drag inside `containerSize`, snap to edges on release.
/// Uses top-leading `offset` (not center `position`) so expand/collapse height changes
/// do not jump the float's top-left anchor.
struct EduDraggableFloat<Content: View>: View {
    var containerSize: CGSize
    var defaultAnchor: SnapAnchor = .topEnd
    var inset: CGFloat = 12
    var magnetic: CGFloat = 32
    var topBias: CGFloat = 160
    var enabled: Bool = true
    @ViewBuilder var content: () -> Content

    @State private var origin: CGPoint = .zero
    @State private var drag: CGSize = .zero
    @State private var selfSize: CGSize = .zero
    @State private var seeded = false
    /// 子视图（工具配置面板）打开时通过 Preference 上报，期间禁用拖拽以免抢走 ScrollView。
    @State private var childBlocksDrag = false

    private var dragEnabled: Bool { enabled && !childBlocksDrag }

    private var renderedOrigin: CGPoint {
        CGPoint(x: origin.x + drag.width, y: origin.y + drag.height)
    }

    var body: some View {
        content()
            .fixedSize()
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: EduFloatSelfSizeKey.self, value: geo.size)
                }
            )
            .onPreferenceChange(EduFloatSelfSizeKey.self) { size in
                // Size updates from collapse must not re-seed or animate origin.
                selfSize = size
                seedIfNeeded()
            }
            .onPreferenceChange(EduFloatBlocksDragKey.self) { blocked in
                if childBlocksDrag != blocked {
                    childBlocksDrag = blocked
                    if blocked {
                        drag = .zero
                    }
                }
            }
            .opacity(seeded ? 1 : 0)
            .offset(x: renderedOrigin.x, y: renderedOrigin.y)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: containerSize) { _ in
                seedIfNeeded(force: !seeded)
            }
            // 不用 highPriorityGesture：否则会抢走内部 ScrollView 的纵向滑动。
            .gesture(
                DragGesture(minimumDistance: 16, coordinateSpace: .global)
                    .onChanged { value in
                        guard dragEnabled, seeded, containerSize.width > 0, selfSize.width > 0 else { return }
                        drag = clampedDelta(value.translation)
                    }
                    .onEnded { _ in
                        guard dragEnabled, seeded else {
                            drag = .zero
                            return
                        }
                        let current = CGPoint(
                            x: origin.x + drag.width,
                            y: origin.y + drag.height
                        )
                        let snapped = snap(current)
                        var commit = Transaction()
                        commit.disablesAnimations = true
                        withTransaction(commit) {
                            origin = current
                            drag = .zero
                        }
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            origin = snapped
                        }
                    }
            )
    }

    private func seedIfNeeded(force: Bool = false) {
        guard (force || !seeded),
              containerSize.width > 1,
              selfSize.width > 1
        else { return }
        origin = seedOrigin()
        seeded = true
    }

    private func seedOrigin() -> CGPoint {
        let maxX = max(inset, containerSize.width - selfSize.width - inset)
        let maxY = max(inset, containerSize.height - selfSize.height - inset)
        let yTop = min(max(topBias, inset), maxY)
        let yMid = min(max((containerSize.height - selfSize.height) / 2, inset), maxY)
        switch defaultAnchor {
        case .topEnd: return CGPoint(x: maxX, y: yTop)
        case .topStart: return CGPoint(x: inset, y: yTop)
        case .bottomEnd: return CGPoint(x: maxX, y: maxY)
        case .bottomStart: return CGPoint(x: inset, y: maxY)
        case .leftCenter: return CGPoint(x: inset, y: yMid)
        case .rightCenter: return CGPoint(x: maxX, y: yMid)
        }
    }

    private func clampedDelta(_ translation: CGSize) -> CGSize {
        let next = CGPoint(x: origin.x + translation.width, y: origin.y + translation.height)
        let c = clamp(next)
        return CGSize(width: c.x - origin.x, height: c.y - origin.y)
    }

    private func clamp(_ o: CGPoint) -> CGPoint {
        let maxX = max(inset, containerSize.width - selfSize.width - inset)
        let maxY = max(inset, containerSize.height - selfSize.height - inset)
        return CGPoint(
            x: min(max(o.x, inset), maxX),
            y: min(max(o.y, inset), maxY)
        )
    }

    private func snap(_ o: CGPoint) -> CGPoint {
        let maxX = max(inset, containerSize.width - selfSize.width - inset)
        let maxY = max(inset, containerSize.height - selfSize.height - inset)
        let midX = (inset + maxX) / 2
        let snapX = o.x <= midX ? inset : maxX
        var snapY = min(max(o.y, inset), maxY)
        if abs(snapY - inset) <= magnetic { snapY = inset }
        else if abs(snapY - maxY) <= magnetic { snapY = maxY }
        return CGPoint(x: snapX, y: snapY)
    }
}

private struct EduFloatSelfSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0 { value = next }
    }
}

/// 子内容（如白板配置面板打开）时置 true，父浮层暂停拖拽。
struct EduFloatBlocksDragKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
