import SwiftUI

struct ClassroomHeaderView: View {
    let snapshot: UiSnapshot
    let title: String
    let elapsedLabel: String
    var brand: String = EduI18n.text("brandName")
    var isPhone: Bool = false
    var onOpenSettings: () -> Void
    var onBack: (() -> Void)? = nil

    /// 顶栏课堂状态：优先 badgeText（权威课堂四态），loading/error 时再覆盖
    private var statusLabel: String {
        switch snapshot.initStatus {
        case .loading: return EduI18n.text("statusConnecting")
        case .error: return EduI18n.text("statusError")
        case .ready: return snapshot.badgeText.isEmpty ? EduI18n.text("statusInProgress") : snapshot.badgeText
        }
    }

    var body: some View {
        if isPhone {
            phoneHeader
        } else {
            desktopHeader
        }
    }

    private var phoneHeader: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                if let onBack {
                    Button(action: onBack) {
                        EduIcon(EduIcons.arrowBack, size: 18, tint: EduColors.onSurface)
                            .padding(4)
                    }
                    .buttonStyle(EduPressButtonStyle())
                }
                Rectangle()
                    .fill(EduColors.outlineVariant)
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, 4)
                Text(EduI18n.text("brandNameShort"))
                    .font(EduFont.sans(18, weight: .bold))
                    .foregroundStyle(EduColors.onSurface)
            }

            VStack(spacing: 2) {
                Text(title)
                    .font(EduFont.sans(13, weight: .semibold))
                    .tracking(0.26)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 150)
                HStack(spacing: 8) {
                    Text(statusLabel.uppercased())
                        .font(EduFont.sans(9, weight: .semibold))
                        .foregroundStyle(EduColors.onSecondaryContainer)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(EduColors.secondaryContainer)
                        .clipShape(Capsule())
                    if !elapsedLabel.isEmpty {
                        Text(elapsedLabel)
                            .font(EduFont.sans(11, weight: .semibold))
                            .foregroundStyle(EduColors.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)

            HStack(spacing: 4) {
                Button {} label: {
                    EduIcon(EduIcons.notifications, size: 20, tint: EduColors.secondary)
                        .padding(8)
                }
                .buttonStyle(EduPressButtonStyle())
                Button(action: onOpenSettings) {
                    EduIcon(EduIcons.settings, size: 20, tint: EduColors.secondary)
                        .padding(8)
                }
                .buttonStyle(EduPressButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: EduDimens.headerHeightPhone)
        .background(EduColors.surfaceLowest)
        .overlay(alignment: .bottom) {
            Rectangle().fill(EduColors.surfaceLow).frame(height: 1)
        }
    }

    private var desktopHeader: some View {
        HStack(spacing: 0) {
            // L2.5 Nexus mark — Path parity with Web `ClassroomHeader.vue` L43–67.
            HStack(spacing: 12) {
                NexusMarkLogo(size: 32)
                Text(brand)
                    .font(EduFont.brand)
                    .foregroundStyle(EduColors.onSurface)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                Text(title)
                    .font(EduFont.title)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                HStack(spacing: 8) {
                    StatusChip(text: statusLabel)
                    if !elapsedLabel.isEmpty {
                        Text(elapsedLabel)
                            .font(EduFont.sans(14, weight: .semibold))
                            .tracking(0.7)
                            .foregroundStyle(EduColors.onSurfaceVariant)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // L2.5 actions gap 16
            HStack(spacing: 16) {
                Button {} label: {
                    EduIcon(EduIcons.notifications, size: 22, tint: EduColors.secondary)
                        .padding(8)
                }
                .buttonStyle(EduPressButtonStyle())
                Button(action: onOpenSettings) {
                    EduIcon(EduIcons.settings, size: 22, tint: EduColors.secondary)
                        .padding(8)
                }
                .buttonStyle(EduPressButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        // L2.5 desktop padding 64pt + bottom border
        .padding(.horizontal, EduDimens.marginDesktop)
        .frame(height: EduDimens.headerHeight)
        .background(EduColors.surfaceLowest)
        .overlay(alignment: .bottom) {
            Rectangle().fill(EduColors.surfaceLow).frame(height: 1)
        }
    }
}

/// L2.5 — SVG-parity Nexus mark. Web reference `ClassroomHeader.vue` L43–67.
struct NexusMarkLogo: View {
    let size: CGFloat
    var body: some View {
        Canvas { ctx, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let stroke: CGFloat = 2.5
            // Outer rounded rect stroke
            let rectPath = Path(roundedRect: CGRect(
                x: stroke / 2, y: stroke / 2,
                width: s - stroke, height: s - stroke
            ), cornerRadius: 3)
            ctx.stroke(rectPath, with: .color(EduColors.primary), lineWidth: stroke)
            // Play triangle 12,10 → 12,22 → 23,16 (viewBox 32)
            let scale = s / 32
            var tri = Path()
            tri.move(to: CGPoint(x: 12 * scale, y: 10 * scale))
            tri.addLine(to: CGPoint(x: 12 * scale, y: 22 * scale))
            tri.addLine(to: CGPoint(x: 23 * scale, y: 16 * scale))
            tri.closeSubpath()
            ctx.fill(tri, with: .color(EduColors.primary))
            // Small circle bottom-right (cx=24, cy=24, r=4, stroke=2 surface-lowest)
            let dot = Path(ellipseIn: CGRect(
                x: 20 * scale, y: 20 * scale, width: 8 * scale, height: 8 * scale
            ))
            ctx.fill(dot, with: .color(EduColors.primaryContainer))
            ctx.stroke(dot, with: .color(EduColors.surfaceLowest), lineWidth: 2)
        }
        .frame(width: size, height: size)
    }
}

struct StatusChip: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(EduFont.sans(10, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(EduColors.onSurfaceVariant)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(EduColors.surfaceLow)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(EduColors.outlineVariant.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - Content Canvas

struct ContentCanvasView: View {
    let document: DemoDocument
    var compact: Bool = false
    var isFullscreen: Bool = false
    /// Trailing inset so landscape stage toggle does not cover header actions.
    var headerEndInset: CGFloat = 0
    var onOpenThumbnails: () -> Void
    var onZoomIn: () -> Void = {}
    var onZoomOut: () -> Void = {}
    var onPrevPage: () -> Void = {}
    var onNextPage: () -> Void = {}
    var onFullscreen: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            // Header 保留外部回调（保持 DemoDocument 显示态），同时把动作转发到 WhiteboardHost。
            DocHeader(
                document: document, compact: compact, isFullscreen: isFullscreen,
                headerEndInset: headerEndInset,
                onOpenThumbnails: onOpenThumbnails,
                onZoomIn: {
                    onZoomIn()
                    WhiteboardHost.shared.zoomIn()
                },
                onZoomOut: {
                    onZoomOut()
                    WhiteboardHost.shared.zoomOut()
                },
                onPrevPage: {
                    guard WhiteboardHost.shared.canPrevPage else { return }
                    if WhiteboardHost.shared.prevBoard() { onPrevPage() }
                },
                onNextPage: {
                    guard WhiteboardHost.shared.canNextPage else { return }
                    if WhiteboardHost.shared.nextBoard() { onNextPage() }
                },
                onFullscreen: onFullscreen
            )
            DocBody(compact: compact)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(EduColors.surfaceLowest)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: compact ? 0 : EduDimens.radiusFull, style: .continuous))
        .padding(compact ? 0 : 16)
        .eduShadow(compact ? .soft : .soft)
    }
}

enum DocHeaderTokens {
    static let actionSpacing: CGFloat = 8
    static let actionEdgePadding: CGFloat = 16
    static let compactBtnIcon: CGFloat = 16
    static let desktopThumbIcon: CGFloat = 18
    static let desktopToolIcon: CGFloat = 20
    static let compactTitleMax: CGFloat = 120
    static let desktopTitleMax: CGFloat = 280
    static let compactHeight: CGFloat = 36
    static let desktopHeight: CGFloat = 48
    static let compactVerticalPadding: CGFloat = 6
    static let dividerH: CGFloat = 20
    static let dividerHorizontalPadding: CGFloat = 4
    static let disabledOpacity: Double = 0.35
    static let fallbackTitle = EduI18n.text("whiteboardFallbackTitle")
}

private struct DocHeader: View {
    let document: DemoDocument
    let compact: Bool
    let isFullscreen: Bool
    var headerEndInset: CGFloat = 0
    let onOpenThumbnails: () -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onPrevPage: () -> Void
    let onNextPage: () -> Void
    let onFullscreen: () -> Void

    // 白板真实状态（board 序号 / 总数 / 缩放百分比）从 host 观察，
    // 与 Android `ContentCanvas.DocHeader` 保持一致。
    @ObservedObject private var host = WhiteboardHost.shared

    private var headerTitle: String {
        if host.hasCourseware {
            host.coursewareTitle.isEmpty ? DocHeaderTokens.fallbackTitle : host.coursewareTitle
        } else {
            DocHeaderTokens.fallbackTitle
        }
    }

    private var whiteboardPermissionDenied: Bool {
        host.localEditRestrictionReason == "permission_denied"
    }

    var body: some View {
        HStack(spacing: DocHeaderTokens.actionSpacing) {
            EduIcon(
                EduIcons.description,
                size: compact ? DocHeaderTokens.compactBtnIcon : DocHeaderTokens.desktopThumbIcon,
                filled: !compact,
                tint: EduColors.onSurfaceVariant
            )
            Text(headerTitle)
                .font(EduFont.sans(compact ? 12 : 14, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(EduColors.onSurface)
                .lineLimit(1)
                .frame(
                    maxWidth: compact ? DocHeaderTokens.compactTitleMax : DocHeaderTokens.desktopTitleMax,
                    alignment: .leading
                )
            Spacer(minLength: 0)
            HStack(spacing: DocHeaderTokens.actionSpacing) {
                if host.hasCourseware {
                    Button(action: onPrevPage) {
                        EduIcon(
                            EduIcons.chevronLeft,
                            size: compact ? DocHeaderTokens.compactBtnIcon : DocHeaderTokens.desktopThumbIcon,
                            tint: EduColors.onSurfaceVariant.opacity(
                                host.canPrevPage && !whiteboardPermissionDenied
                                    ? 1 : DocHeaderTokens.disabledOpacity
                            )
                        )
                    }
                    .buttonStyle(EduPressButtonStyle())
                    .disabled(!host.canPrevPage || whiteboardPermissionDenied)
                    Text("\(host.boardIndex) / \(host.boardTotal)")
                        .font(EduFont.sans(compact ? 11 : 12, weight: .semibold))
                        .tracking(compact ? 0.5 : 0.6)
                        .foregroundStyle(EduColors.onSurfaceVariant)
                    Button(action: onNextPage) {
                        EduIcon(
                            EduIcons.chevronRight,
                            size: compact ? DocHeaderTokens.compactBtnIcon : DocHeaderTokens.desktopThumbIcon,
                            tint: EduColors.onSurfaceVariant.opacity(
                                host.canNextPage && !whiteboardPermissionDenied
                                    ? 1 : DocHeaderTokens.disabledOpacity
                            )
                        )
                    }
                    .buttonStyle(EduPressButtonStyle())
                    .disabled(!host.canNextPage || whiteboardPermissionDenied)
                    Button(action: onOpenThumbnails) {
                        EduIcon(
                            EduIcons.gridView,
                            size: compact ? DocHeaderTokens.compactBtnIcon : DocHeaderTokens.desktopThumbIcon,
                            tint: EduColors.onSurfaceVariant
                        )
                    }
                    .buttonStyle(EduPressButtonStyle())
                    Rectangle().fill(EduColors.outlineVariant.opacity(0.3))
                        .frame(width: 1, height: DocHeaderTokens.dividerH)
                        .padding(.horizontal, DocHeaderTokens.dividerHorizontalPadding)
                }
                if !compact {
                    Button(action: onZoomOut) {
                        EduIcon(EduIcons.zoomOut, size: DocHeaderTokens.desktopToolIcon, tint: EduColors.onSurfaceVariant)
                    }
                    .buttonStyle(EduPressButtonStyle())
                    Text("\(host.boardScalePercent)%")
                        .font(EduFont.sans(12, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(EduColors.onSurfaceVariant)
                    Button(action: onZoomIn) {
                        EduIcon(EduIcons.zoomIn, size: DocHeaderTokens.desktopToolIcon, tint: EduColors.onSurfaceVariant)
                    }
                    .buttonStyle(EduPressButtonStyle())
                    Rectangle().fill(EduColors.outlineVariant.opacity(0.3))
                        .frame(width: 1, height: DocHeaderTokens.dividerH)
                        .padding(.horizontal, DocHeaderTokens.dividerHorizontalPadding)
                }
                Button(action: onFullscreen) {
                    EduIcon(
                        isFullscreen ? EduIcons.fullscreenExit : EduIcons.fullscreen,
                        size: compact ? DocHeaderTokens.compactBtnIcon : DocHeaderTokens.desktopToolIcon,
                        tint: EduColors.onSurfaceVariant
                    )
                }
                .buttonStyle(EduPressButtonStyle())
                .accessibilityLabel(isFullscreen ? EduI18n.text("ariaExitFullscreen") : EduI18n.text("ariaFullscreen"))
            }
        }
        .padding(.leading, DocHeaderTokens.actionEdgePadding)
        .padding(.trailing, DocHeaderTokens.actionEdgePadding + headerEndInset)
        .padding(.vertical, compact ? DocHeaderTokens.compactVerticalPadding : 0)
        .frame(height: compact ? DocHeaderTokens.compactHeight : DocHeaderTokens.desktopHeight)
        .background(EduTint.surfaceLow50)
        .overlay(alignment: .bottom) {
            Rectangle().fill(EduColors.surfaceLow).frame(height: 1)
        }
    }
}

/// Body 直接挂 `WhiteboardCanvas`；所有布局均以 16:9 contain 并在可用区域双向居中。
///
/// 与 Android `ContentCanvas.DocBody` 一致：header 上的所有分页/缩放动作
/// 已经由 `WhiteboardHost.shared` 转发到 DrawsKit。
private struct DocBody: View {
    let compact: Bool
    var body: some View {
        GeometryReader { geo in
            let inset = compact ? 0 : DocBodyTokens.desktopInset
            let availableWidth = max(0, geo.size.width - inset * 2)
            let availableHeight = max(0, geo.size.height - inset * 2)
            let byHeight = availableHeight * WhiteboardLayoutDefaults.aspectRatio
            let pageWidth = min(availableWidth, byHeight)
            ZStack {
                if compact {
                    WhiteboardCanvas()
                        .frame(width: pageWidth)
                        .aspectRatio(WhiteboardLayoutDefaults.aspectRatio, contentMode: .fit)
                        .background(EduColors.surfaceLowest)
                } else {
                    WhiteboardCanvas()
                        .frame(width: pageWidth)
                        .aspectRatio(WhiteboardLayoutDefaults.aspectRatio, contentMode: .fit)
                        .background(EduColors.surfaceLowest)
                        .clipShape(RoundedRectangle(cornerRadius: EduDimens.radius, style: .continuous))
                        .eduShadow(.soft)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(inset)
            .background(EduTint.surfaceLow20)
        }
    }
}

private enum DocBodyTokens {
    static let desktopInset: CGFloat = 16
}
