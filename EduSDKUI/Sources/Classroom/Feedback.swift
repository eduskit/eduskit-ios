import Foundation
import EduSDK

public enum FeedbackMode: String, Decodable { case toast, dialog, notification }
public enum FeedbackTone: String, Decodable { case info, success, warning, error }
public enum FeedbackActionStyle: String, Decodable { case text, primary, danger }
public struct FeedbackDiagnostic: Decodable {
    public let code: String
    public let message: String?
    public let traceId: String?
}
public struct FeedbackAction: Identifiable {
    public let id: String
    public let label: String
    public let style: FeedbackActionStyle
    public let dismissOnClick: Bool
    public init(id: String, label: String, style: FeedbackActionStyle = .text, dismissOnClick: Bool = true) {
        self.id = id; self.label = label; self.style = style; self.dismissOnClick = dismissOnClick
    }
}
public struct UiFeedback: Identifiable {
    public let id: UInt64
    public let mode: FeedbackMode
    public let tone: FeedbackTone
    public let message: String
    public let detail: String?
    public let diagnostic: FeedbackDiagnostic?
    public let dismissible: Bool
    public let autoDismissMs: UInt64?
    public let modal: Bool
    public let dismissOnBackdrop: Bool
    public let actions: [FeedbackAction]
    public let busyActionIds: Set<String>
}
public struct FeedbackRequest {
    public let id: UInt64
    let input: () -> [String: Any]
    @MainActor public static func create(mode: FeedbackMode, tone: FeedbackTone, message: String,
        autoDismissMs: UInt64?, detail: String? = nil, dismissible: Bool = true,
        modal: Bool = false, dismissOnBackdrop: Bool = false, actions: [FeedbackAction] = []) -> FeedbackRequest {
        let id = FeedbackIdentity.next()
        return FeedbackRequest(id: id, input: { ["type": "present", "feedback": ["id": String(id), "spec": [
            "mode": mode.rawValue, "tone": tone.rawValue, "message": literal(message),
            "detail": detail.map(literal) as Any? ?? NSNull(), "diagnostic": NSNull(),
            "dismissible": dismissible, "modal": modal, "dismissOnBackdrop": dismissOnBackdrop,
            "autoDismissMs": autoDismissMs as Any? ?? NSNull(), "dedupKey": NSNull(), "group": NSNull(),
            "actions": actions.map { ["id": $0.id, "label": literal($0.label), "style": $0.style.rawValue, "dismissOnClick": $0.dismissOnClick] }
        ]]] })
    }
}
private func literal(_ text: String) -> [String: Any] { ["kind": "literal", "text": text] }
@MainActor private enum FeedbackIdentity {
    static var sequence: UInt64 = 0
    static func next() -> UInt64 { sequence += 1; return sequence }
}
@MainActor private func source(_ type: String, _ values: [String: Any] = [:]) -> FeedbackRequest {
    let id = FeedbackIdentity.next()
    return FeedbackRequest(id: id, input: { var source = values; source["type"] = type
        return ["type": "present_source", "id": String(id), "source": source] })
}
let classroomStatusStartAction = "start-class"
let endClassConfirmAction = "end-class-confirm"
let endClassCancelAction = "end-class-cancel"
let mediaOpenHintActionOpenMic = "open-mic"
let mediaOpenHintActionOpenCamera = "open-camera"
let mediaOpenHintActionCheckDevices = "check-devices"
let mediaOpenHintActionGotIt = "got-it"


@MainActor func feedbackFromMediaOpenHint(audience: MediaOpenHintAudience) -> FeedbackRequest {
    source("media_open_hint", ["audience": audience == .teacher ? "teacher" : "student"])
}
@MainActor func feedbackFromMediaCaptureFailure() -> FeedbackRequest { source("media_capture_failure") }
@MainActor func feedbackFromEndClassConfirm(localeTag: String? = nil) -> FeedbackRequest { source("end_class_confirm") }
func interactionRestrictionMessage(action: String, reason: String, localeTag: String? = nil) -> String {
    reason == "classroom_not_started" ? EduI18n.text("restrictionNotStarted", ["action": classroomActionLabel(action, localeTag: localeTag)], localeTag: localeTag)
        : EduI18n.text("restrictionHint_" + reason, localeTag: localeTag)
}
@MainActor func interactionRestrictionFeedback(action: String, reason: String, localeTag: String? = nil) -> FeedbackRequest {
    source("restriction", ["actionLabel": classroomActionLabel(action, localeTag: localeTag), "reason": reason])
}
@MainActor func permissionChangedFeedback(actions: [String], allowed: Bool, localeTag: String? = nil) -> FeedbackRequest {
    source("permission_change", ["actionLabels": actions, "allowed": allowed, "separator": EduI18n.text("permissionChangedSeparator", localeTag: localeTag)])
}
@MainActor func feedback(from status: ClassroomLifecycleStatus, canStart: Bool, localeTag: String? = nil) -> FeedbackRequest {
    source("classroom_status", ["status": status.rawValue, "canStart": canStart])
}
@MainActor func feedback(from error: SdkError, duringInitialization: Bool, localeTag: String? = nil) -> FeedbackRequest {
    source("error", ["code": error.code, "message": error.message, "duringInitialization": duringInitialization])
}

private struct WireText: Decodable {
    let kind: String
    let key: String?
    let args: [String: String]?
    let text: String?
    func resolve(locale: String?) throws -> String {
        if kind == "catalog", let key, let args { return EduI18n.text(key, args, localeTag: locale) }
        if kind == "literal", let text { return text }
        throw FeedbackProjectionError.invalidResponse
    }
}
private struct WireAction: Decodable { let id: String; let label: WireText; let style: FeedbackActionStyle; let dismissOnClick: Bool }
private struct WireSpec: Decodable {
    let mode: FeedbackMode; let tone: FeedbackTone; let message: WireText; let detail: WireText?
    let diagnostic: FeedbackDiagnostic?; let dismissible: Bool; let autoDismissMs: UInt64?
    let modal: Bool; let dismissOnBackdrop: Bool; let actions: [WireAction]
}
private struct WireItem: Decodable {
    let id: String; let spec: WireSpec
    func project(locale: String?, busy: Set<String>) throws -> UiFeedback {
        guard let id = UInt64(id) else { throw FeedbackProjectionError.invalidResponse }
        return UiFeedback(id: id, mode: spec.mode, tone: spec.tone, message: try spec.message.resolve(locale: locale),
            detail: try spec.detail?.resolve(locale: locale), diagnostic: spec.diagnostic, dismissible: spec.dismissible,
            autoDismissMs: spec.autoDismissMs, modal: spec.modal, dismissOnBackdrop: spec.dismissOnBackdrop,
            actions: try spec.actions.map { FeedbackAction(id: $0.id, label: try $0.label.resolve(locale: locale), style: $0.style, dismissOnClick: $0.dismissOnClick) }, busyActionIds: busy)
    }
}
enum FeedbackProjectionError: Error { case invalidResponse }
public struct FeedbackReceipt: Decodable {
    public let type: String; public let feedbackId: String; public let actionId: String?; public let reason: String?
}
public struct FeedbackFrame {
    public let current: UiFeedback?; public let queue: [UiFeedback]; public let receipts: [FeedbackReceipt]; public let nextWakeMs: UInt64?
}
private struct WireFrame: Decodable {
    let current: WireItem?; let queue: [WireItem]; let effects: [FeedbackReceipt]; let nextWakeMs: UInt64?; let busyActionIds: [String]
}
func projectFeedbackFrame(_ object: [String: Any], locale: String?) throws -> FeedbackFrame {
    let wire = try JSONDecoder().decode(WireFrame.self, from: JSONSerialization.data(withJSONObject: object))
    return FeedbackFrame(current: try wire.current?.project(locale: locale, busy: Set(wire.busyActionIds)),
        queue: try wire.queue.map { try $0.project(locale: locale, busy: []) }, receipts: wire.effects, nextWakeMs: wire.nextWakeMs)
}
