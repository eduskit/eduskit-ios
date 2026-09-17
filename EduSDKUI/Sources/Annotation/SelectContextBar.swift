import SwiftUI

struct SelectContextBarView: View {
    @ObservedObject private var host = WhiteboardHost.shared

    var body: some View {
        if !host.selection.isEmpty {
            HStack(spacing: 2) {
                ctxIcon(EduIcons.contentCopy) { host.copySelected() }
                ctxIcon(EduIcons.delete) { host.deleteSelected() }
                sep
                ctxIcon(EduIcons.lock) { host.lockSelected(true) }
                ctxIcon(EduIcons.lockOpen) { host.lockSelected(false) }
                sep
                ctxIcon(EduIcons.verticalAlignTop) { host.bringSelectedToFront() }
                ctxIcon(EduIcons.verticalAlignBottom) { host.sendSelectedToBack() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(EduColors.surfaceLowest))
            .overlay(Capsule().stroke(EduColors.surfaceLow, lineWidth: 1))
            .eduShadow(.soft)
        }
    }

    private var sep: some View {
        Rectangle()
            .fill(EduColors.outlineVariant.opacity(0.45))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 4)
    }

    private func ctxIcon(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            EduIcon(icon, size: 16, tint: EduColors.onSurfaceVariant)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(EduPressButtonStyle())
    }
}
