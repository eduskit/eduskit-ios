import CoreGraphics

/// 课件可见页资源加载状态（对齐 DK_COURSEWARE_STATUS_CHANGED）
enum CoursewareLoadStatus {
    static let loading = "loading"
    static let ready = "ready"
    static let error = "error"
}

/// 白板课件加载遮罩 token（与 Web CoursewareLoadingOverlayTokens 对齐）
enum CoursewareLoadingOverlayTokens {
    static let fontSize: CGFloat = 13
    static let padding: CGFloat = 16
    /// 白底半透明遮罩 opacity（对齐 Web color-mix 88%）
    static let scrimOpacity: Double = 0.88
    static let zIndex: Double = 2
}

enum CoursewareLoadingStrings {
    static let `default` = EduI18n.text("coursewarePageLoading")
    static let errorFallback = EduI18n.text("coursewarePageLoadError")
}
