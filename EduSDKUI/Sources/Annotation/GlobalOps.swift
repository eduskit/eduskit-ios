import SwiftUI

struct GlobalOpsView: View {
    @ObservedObject private var host = WhiteboardHost.shared
    var compact: Bool = false

    private var canPrev: Bool {
        if host.hasCourseware {
            return host.canPrevPage
        }
        return host.boardTotal > 1
    }

    private var canNext: Bool {
        if host.hasCourseware {
            return host.canNextPage
        }
        return host.boardTotal > 1
    }

    var body: some View {
        HStack(spacing: compact ? 0 : 2) {
            opsIcon(EduIcons.undo, enabled: host.history.canUndo) { host.undo() }
            opsIcon(EduIcons.redo, enabled: host.history.canRedo) { host.redo() }
            opsIcon(EduIcons.deleteSweep, danger: true) { host.clear() }
            sep
            opsIcon(EduIcons.zoomOut) { host.zoomOut() }
            Button { host.fitZoom() } label: {
                Text("\(host.boardScalePercent)%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(EduColors.onSurfaceVariant)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            opsIcon(EduIcons.zoomIn) { host.zoomIn() }
            opsIcon(EduIcons.fitScreen) { host.fitZoom() }
            sep
            opsIcon(EduIcons.chevronLeft, enabled: canPrev) {
                if canPrev { host.prevBoard() }
            }
            Text("\(host.boardIndex) / \(host.boardTotal)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(EduColors.onSurfaceVariant)
                .padding(.horizontal, 6)
            opsIcon(EduIcons.chevronRight, enabled: canNext) {
                if canNext { host.nextBoard() }
            }
            if !host.hasCourseware {
                opsIcon(EduIcons.add) { _ = host.addBoard() }
            }
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 4)
        .background(Capsule().fill(EduColors.surfaceLowest))
        .overlay(Capsule().stroke(EduColors.surfaceLow, lineWidth: 1))
        .eduShadow(.soft)
    }

    private var sep: some View {
        Rectangle()
            .fill(EduColors.outlineVariant.opacity(0.45))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 4)
    }

    private func opsIcon(
        _ icon: String,
        enabled: Bool = true,
        danger: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            EduIcon(
                icon,
                size: 18,
                tint: !enabled ? EduColors.onSurfaceVariant.opacity(0.35)
                    : danger ? EduColors.error : EduColors.onSurfaceVariant
            )
            .frame(width: 30, height: 30)
        }
        .buttonStyle(EduPressButtonStyle())
        .disabled(!enabled)
    }
}
