import Foundation
import EduSDK

/// 底部工具栏入口的渲染结论。
///
/// 可见性与可用性全部来自 Core 的 `interaction_policy`，UI 不再按身份、上台状态
/// 或权限自行推导；这里只负责把 `ActionAvailability` 翻译成按钮属性和文案。
public struct ToolbarEntry: Equatable {
    /// 为 false 时必须整条隐藏，而不是置灰——当前身份根本没有这条能力。
    public let visible: Bool
    public let disabled: Bool
    /// 不可用时的提示；可用时为 nil。
    public let hint: String?

    public init(visible: Bool, disabled: Bool, hint: String? = nil) {
        self.visible = visible
        self.disabled = disabled
        self.hint = hint
    }
}

enum ToolbarActionDefaults {
    static let hidden = ToolbarEntry(visible: false, disabled: true)
    /// 受限原因直接拼 catalog key，六端一致，不做任何 `switch`。
    static let restrictionHintKeyPrefix = "restrictionHint_"
    static let capabilityNotReady = "capability_not_ready"
    /// 能力名称同样直接拼 catalog key，六端一致，不做任何 `switch`。
    static let classroomActionLabelKeyPrefix = "classroomAction_"
    /// 底部栏会渲染的 action，与 Web `FloatingToolbar` / `MobileBottomBar` 一致。
    static let actions = [
        "use_microphone",
        "use_camera",
        "raise_hand",
        "share_screen",
        "operate_courseware",
        "start_class",
        "manage_own_stage",
    ]
}

public func toolbarEntry(_ policy: [ActionAvailability], _ action: String) -> ToolbarEntry {
    guard let availability = policy.first(where: { $0.action == action }), availability.visible else {
        // 策略尚未就绪时按隐藏处理：宁可少画一个入口，也不画一个点了会报错的按钮。
        return ToolbarActionDefaults.hidden
    }
    if availability.available { return ToolbarEntry(visible: true, disabled: false) }
    let reason = availability.reason ?? ToolbarActionDefaults.capabilityNotReady
    return ToolbarEntry(
        visible: true,
        disabled: reason == "permission_denied",
        hint: EduI18n.text(ToolbarActionDefaults.restrictionHintKeyPrefix + reason)
    )
}

/// 工具栏一次性取齐全部入口，避免每个 View 各自遍历策略列表。
public func toolbarEntries(_ policy: [ActionAvailability]) -> [String: ToolbarEntry] {
    Dictionary(uniqueKeysWithValues: ToolbarActionDefaults.actions.map { ($0, toolbarEntry(policy, $0)) })
}

public extension Dictionary where Key == String, Value == ToolbarEntry {
    /// 缺席视为隐藏：策略尚未就绪时宁可少画一个入口。
    func entry(_ action: String) -> ToolbarEntry {
        self[action] ?? ToolbarActionDefaults.hidden
    }
}

/// 置灰时在标签尾部补一个「未开放」后缀，对齐 Web 底部栏。
public func restrictedLabel(_ label: String, _ entry: ToolbarEntry) -> String {
    entry.disabled ? "\(label) · \(EduI18n.text("permissionUnavailableShort"))" : label
}

/// 能力名称。新增 ClassroomAction 时只需往语言包补一条同名文案。
func classroomActionLabel(_ action: String, localeTag: String? = nil) -> String {
    EduI18n.text(ToolbarActionDefaults.classroomActionLabelKeyPrefix + action, localeTag: localeTag)
}
