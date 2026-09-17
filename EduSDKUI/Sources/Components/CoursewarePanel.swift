import SwiftUI
import EduSDK

private enum CoursewareUiDefaults {
    static let statusReady = "ready"
    static let listMaxHeight: CGFloat = 360
    static let panelPadding: CGFloat = 20
}

/// 课堂课件列表面板：数据来自 Headless `getClassroomCourseware`，使用时拉 manifest 并加载白板。
struct CoursewarePanelView: View {
    let controller: ClassroomController
    var onDismiss: () -> Void

    @State private var items: [Courseware] = []
    @State private var loadingId: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(EduI18n.text("coursewarePanelTitle"))
                    .font(EduFont.sans(18, weight: .semibold))
                Spacer()
                Button(action: onDismiss) {
                    EduIcon(EduIcons.close, size: 22, tint: EduColors.onSurfaceVariant)
                }
                .buttonStyle(EduPressButtonStyle())
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(EduFont.sans(13))
                    .foregroundStyle(EduColors.error)
            }

            if items.isEmpty {
                Text(EduI18n.text("coursewareEmpty"))
                    .font(EduFont.sans(14))
                    .foregroundStyle(EduColors.onSurfaceVariant)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(items, id: \.id) { item in
                            CoursewareRowView(
                                item: item,
                                loading: loadingId == item.id,
                                onUse: { useCourseware(item) }
                            )
                        }
                    }
                }
                .frame(maxHeight: CoursewareUiDefaults.listMaxHeight)
            }
        }
        .padding(CoursewareUiDefaults.panelPadding)
        .eduGlass(cornerRadius: EduDimens.radius2xl, borderColor: EduColors.surfaceLow, tier: .soft)
        .padding(40)
        .onAppear {
            controller.loadClassroomCourseware { items = $0 }
        }
    }

    private func useCourseware(_ item: Courseware) {
        guard item.status == CoursewareUiDefaults.statusReady, loadingId == nil else { return }
        errorMessage = nil
        loadingId = item.id
        // Controller 负责把 manifest HTTP 放到后台队列，completion 回主线程。
        controller.useCourseware(coursewareId: item.id) { result in
            loadingId = nil
            switch result {
            case .success:
                onDismiss()
            case .failure(let err):
                errorMessage = err.localizedDescription
            }
        }
    }
}

private struct CoursewareRowView: View {
    let item: Courseware
    let loading: Bool
    var onUse: () -> Void

    private var ready: Bool { item.status == CoursewareUiDefaults.statusReady }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(EduFont.sans(15, weight: .semibold))
                    .lineLimit(1)
                Text(statusLabel(item))
                    .font(EduFont.sans(12))
                    .foregroundStyle(EduColors.onSurfaceVariant)
            }
            Spacer(minLength: 8)
            Button(action: onUse) {
                Text(loading ? EduI18n.text("coursewareUsing") : EduI18n.text("coursewareUse"))
                    .font(EduFont.sans(13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(EduColors.primary)
            .disabled(!ready || loading)
        }
        .padding(.vertical, 4)
    }

    private func statusLabel(_ item: Courseware) -> String {
        switch item.status {
        case CoursewareUiDefaults.statusReady:
            return EduI18n.text("coursewareStatusReady")
        case "processing", "queued", "uploading":
            return EduI18n.text("coursewareTranscoding", ["progress": item.progress])
        case "failed":
            if let msg = item.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !msg.isEmpty {
                return EduI18n.text("coursewareTranscodeFailed", ["message": msg])
            }
            return EduI18n.text("coursewareStatusFailed")
        default:
            return item.status.isEmpty ? EduI18n.text("coursewareStatusUnknown") : item.status
        }
    }
}
