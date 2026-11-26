import SwiftUI

struct ChatHistoryControls {
    var loading = false
    var hasMore = true
    var error = false
    var load: () -> Void = {}
    var ready = false
    /// Core 下发的终态占位 catalog key；UI 只渲染，不自行区分结束与过期。
    var notice: String?
}
private struct ChatHistoryControlsKey: EnvironmentKey { static let defaultValue = ChatHistoryControls() }
extension EnvironmentValues {
    var chatHistoryControls: ChatHistoryControls {
        get { self[ChatHistoryControlsKey.self] }
        set { self[ChatHistoryControlsKey.self] = newValue }
    }
}
