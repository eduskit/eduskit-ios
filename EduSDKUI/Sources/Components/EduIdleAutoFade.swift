import SwiftUI

/// Small tick source that lets sibling views wake each other up when the user interacts.
/// Bump `tick` (any call site) → any `.eduIdleAutoSlide(activity:)` observer resets its timer.
public final class EduActivityTicker: ObservableObject {
    @Published public private(set) var tick: Int = 0
    @Published public private(set) var visible = true

    public init() {}

    public func bump() {
        tick &+= 1
        visible = true
    }

    fileprivate func show() { visible = true }
    fileprivate func hide() { visible = false }
}

/// Which screen edge the content slides off toward when idle.
public enum EduSlideEdge {
    case top, bottom
}

/// After `interval` seconds of no `activity` bumps, slides its content off toward `edge`.
/// A new bump slides it back on. Pauses (stays visible) while `paused == true`.
/// Content remains mounted so internal state (mic/cam toggles etc.) is preserved.
struct EduIdleAutoSlide: ViewModifier {
    // Observed so any `tick` change re-runs `body()` and fires the onChange below.
    @ObservedObject var activity: EduActivityTicker
    let edge: EduSlideEdge
    var interval: TimeInterval = 5
    var paused: Bool = false
    /// Extra distance beyond the measured height, so shadows/glows also clear the edge.
    var overshoot: CGFloat = 40

    @State private var pending: DispatchWorkItem?
    @State private var measuredHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: EduSlideSizeKey.self, value: geo.size.height)
                }
            )
            .onPreferenceChange(EduSlideSizeKey.self) { measuredHeight = $0 }
            .offset(y: hiddenOffset)
            .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.32), value: activity.visible)
            .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.32), value: measuredHeight)
            .allowsHitTesting(activity.visible)
            .onAppear { schedule() }
            .onDisappear { pending?.cancel() }
            .onChange(of: activity.tick) { _ in wake() }
            .onChange(of: paused) { p in
                if p {
                    pending?.cancel()
                    activity.show()
                } else {
                    schedule()
                }
            }
    }

    private var hiddenOffset: CGFloat {
        guard !activity.visible else { return 0 }
        let distance = max(measuredHeight, 0) + overshoot
        return edge == .top ? -distance : distance
    }

    private func wake() {
        activity.show()
        schedule()
    }

    private func schedule() {
        pending?.cancel()
        guard !paused else { return }
        let work = DispatchWorkItem { activity.hide() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: work)
    }
}

private struct EduSlideSizeKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

extension View {
    /// Auto-hide by sliding off toward `edge` after `interval` of no `activity` bumps.
    func eduIdleAutoSlide(
        activity: EduActivityTicker,
        edge: EduSlideEdge,
        interval: TimeInterval = 5,
        paused: Bool = false
    ) -> some View {
        modifier(
            EduIdleAutoSlide(
                activity: activity,
                edge: edge,
                interval: interval,
                paused: paused
            )
        )
    }
}
