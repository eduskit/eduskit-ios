import SwiftUI
import UIKit
import DrawsKit

public enum WhiteboardLayoutDefaults {
    public static let ratio = "16:9"
    public static let aspectRatio: CGFloat = 16.0 / 9.0
}

/// 白板初始化参数，透传到 `DrawsKit`。字段与 Android 端 `WhiteboardConfig` 对齐。
public struct WhiteboardConfig: Equatable {
    public var id: String
    public var roomId: String
    public var appId: String
    public var userId: String
    public var token: String
    public var serverEnvironment: String
    public var serverHost: String?

    public init(
        id: String = "whiteboard",
        roomId: String = "edu-demo-room",
        appId: String = "1400000000",
        userId: String = "demo_user",
        token: String = "demo_sig",
        serverEnvironment: String = WhiteboardServerDefaults.environment,
        serverHost: String? = nil
    ) {
        self.id = id
        self.roomId = roomId
        self.appId = appId
        self.userId = userId
        self.token = token
        self.serverEnvironment = serverEnvironment
        self.serverHost = serverHost
    }
}

/// 真实白板画布：挂载期间把会话级常驻 `DrawsKitView` reparent 到当前槽位。
///
/// - 生命周期：`DrawsKit` + `DrawsKitView` 由 `WhiteboardHost` 会话持有。
///   Mobile↔Landscape 整树替换时 **只换父视图**，不 detach / 不重建引擎与 renderer。
///   离开课堂调用 `WhiteboardHost.endSession()`。
/// - `NativeEngine.isLibLoaded` 为 false 时展示 `WhiteboardUnavailableView`。
public struct WhiteboardCanvas: View {
    public var config: WhiteboardConfig
    @ObservedObject private var host = WhiteboardHost.shared

    public init(config: WhiteboardConfig = WhiteboardConfig()) {
        self.config = config
    }

    public var body: some View {
        if NativeEngine.isLibLoaded {
            if host.hasJoinCredentials {
                ZStack {
                    WhiteboardCanvasRepresentable(config: config)
                    if host.engineReady && host.coursewareLoading {
                        CoursewareLoadingOverlayView(
                            message: host.coursewareLoadMessage.isEmpty
                                ? CoursewareLoadingStrings.default
                                : host.coursewareLoadMessage
                        )
                    }
                    if host.engineReady && !host.localEditEnabled &&
                        host.localEditRestrictionReason == "classroom_not_started" {
                        WhiteboardWaitingOverlayView()
                    }
                    // Keep one UI Kit loading surface visible from credential wait through
                    // DrawsKit ready(). Its native bootstrap overlay stays below this SwiftUI
                    // layer, so mounting the canvas cannot look like a second loading pass.
                    if !host.engineReady {
                        WhiteboardConnectionStateView(
                            failed: host.engineFailed,
                            disabled: false
                        )
                    }
                }
            } else {
                WhiteboardConnectionStateView(
                    failed: host.joinProgress.whiteboard == .failed,
                    disabled: host.joinProgress.whiteboard == .disabled &&
                        (host.joinProgress.phase == .domainsInitializing || host.joinProgress.phase == .joined)
                )
            }
        } else {
            WhiteboardUnavailableView()
                .onAppear { WhiteboardHost.shared.markEngineReady(false, report: false) }
        }
    }
}

private struct WhiteboardWaitingOverlayView: View {
    var body: some View {
        HStack(spacing: 12) {
            EduIcon(EduIcons.lock, size: 20, tint: EduColors.primary)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(EduColors.surfaceLow)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(EduI18n.text("whiteboardWaitingTitle"))
                    .font(EduFont.sans(14, weight: .semibold))
                    .foregroundStyle(EduColors.onSurface)
                Text(EduI18n.text("whiteboardWaitingHint"))
                    .font(EduFont.sans(12))
                    .foregroundStyle(EduColors.onSurfaceVariant)
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: 380, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(EduColors.surfaceLowest.opacity(0.96))
                .shadow(color: Color.black.opacity(0.1), radius: 16, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(EduColors.outlineVariant, lineWidth: 1)
        )
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EduColors.surfaceLow.opacity(0.18))
        .contentShape(Rectangle())
        .zIndex(2)
    }
}

private struct WhiteboardConnectionStateView: View {
    let failed: Bool
    let disabled: Bool

    private var title: String {
        if failed { return EduI18n.text("whiteboardInitializationTitle") }
        if disabled { return EduI18n.text("whiteboardDisabled") }
        return EduI18n.text("whiteboardConnecting")
    }

    var body: some View {
        VStack(spacing: 12) {
            EduIcon(
                failed ? EduIcons.warning : EduIcons.pending,
                size: 32,
                tint: EduColors.onSurfaceVariant
            )
            Text(title)
                .font(EduFont.sans(14, weight: .semibold))
                .foregroundStyle(EduColors.onSurface)
                .multilineTextAlignment(.center)
            if failed {
                Text(EduI18n.text("restrictionCapability"))
                    .font(EduFont.sans(12))
                    .foregroundStyle(EduColors.onSurfaceVariant)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(EduColors.surfaceLow)
    }
}

private struct CoursewareLoadingOverlayView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(EduFont.sans(CoursewareLoadingOverlayTokens.fontSize, weight: .semibold))
            .foregroundStyle(EduColors.onSurfaceVariant)
            .multilineTextAlignment(.center)
            .padding(CoursewareLoadingOverlayTokens.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(CoursewareLoadingOverlayTokens.scrimOpacity))
            .allowsHitTesting(false)
            .zIndex(CoursewareLoadingOverlayTokens.zIndex)
    }
}

// MARK: - UIViewRepresentable

private struct WhiteboardCanvasRepresentable: UIViewRepresentable {
    let config: WhiteboardConfig

    /// `DrawsKitView` is session-persistent and is reparented when SwiftUI swaps
    /// portrait/landscape classroom trees. Auto Layout can leave that reused
    /// view at the previous host's bounds for a render turn, so Core receives a
    /// stale viewport (for example 402x375 inside a visible 402x226 slot). Keep
    /// the render surface's frame identical to the actually visible host on
    /// every UIKit layout pass.
    private final class SurfaceHostView: UIView {
        weak var surface: UIView?

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let surface else { return }
            if surface.frame != bounds {
                surface.frame = bounds
            }
            // Frame assignment does not always recurse into DrawsKitView.layoutSubviews,
            // so Core can keep a stale viewport after reparent (e.g. 402×375 in a
            // visible 402×226 slot) and crop a 16:9 courseware page.
            surface.setNeedsLayout()
            surface.layoutIfNeeded()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(config: config)
    }

    func makeUIView(context: Context) -> UIView {
        let host = SurfaceHostView()
        host.backgroundColor = .white
        host.clipsToBounds = true
        // make 阶段允许抢占：新布局的 surface 槽位优先生效。
        context.coordinator.installSurface(in: host, claimIfOwnedByOther: true)
        return host
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // update 不得从另一活着的 host 抢 surface，否则旧树在 dismantle 前会把新挂载拽回去。
        context.coordinator.installSurface(in: uiView, claimIfOwnedByOther: false)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        // 不 detach 引擎：surface 是会话级常驻，下一布局会 reparent。
        WhiteboardHost.shared.releaseSurfaceHost(uiView)
    }

    final class Coordinator {
        let config: WhiteboardConfig

        init(config: WhiteboardConfig) {
            self.config = config
        }

        func installSurface(in host: UIView, claimIfOwnedByOther: Bool) {
            guard let surface = WhiteboardHost.shared.acquireSurface(config: config) else { return }
            if let owner = surface.superview, owner !== host {
                guard claimIfOwnedByOther else { return }
                surface.removeFromSuperview()
            }
            if surface.superview !== host {
                // Frame/autoresizing is intentional here. The surface survives
                // SwiftUI layout-tree replacement, while constraints belong to
                // one particular host and can preserve its obsolete bounds for
                // a frame after reparenting.
                surface.translatesAutoresizingMaskIntoConstraints = true
                surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                surface.frame = host.bounds
                host.addSubview(surface)
            }
            (host as? SurfaceHostView)?.surface = surface
            host.setNeedsLayout()
            host.layoutIfNeeded()
            WhiteboardHost.shared.bindPersistentSurface(config: config, boardContainer: host)
        }
    }
}

// MARK: - Fallback

/// FFI 未加载时的兜底视图：告知使用方架构限制。iOS 侧通常只在极端情况下命中。
private struct WhiteboardUnavailableView: View {
    var body: some View {
        VStack(spacing: 12) {
            EduIcon(EduIcons.ext, size: 32, tint: EduColors.onSurfaceVariant)
            Text(EduI18n.text("whiteboardNativeMissing"))
                .font(EduFont.sans(14, weight: .semibold))
                .foregroundStyle(EduColors.onSurface)
            Text(
                """
                白板组件暂时不可用，请退出课堂后重试。
                """
            )
            .font(EduFont.sans(12))
            .foregroundStyle(EduColors.onSurfaceVariant)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(EduColors.surfaceLow)
    }
}
