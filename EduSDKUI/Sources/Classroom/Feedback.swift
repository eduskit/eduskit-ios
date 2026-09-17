import Foundation
import EduSDK

public enum FeedbackMode { case toast, dialog, notification }
public enum FeedbackTone { case info, success, warning, error }
public enum FeedbackActionStyle { case text, primary, danger }

public struct FeedbackDiagnostic {
    public let code: String
    public let message: String?
    public let traceId: String?

    public init(code: String, message: String? = nil, traceId: String? = nil) {
        self.code = code
        self.message = message
        self.traceId = traceId
    }
}

public struct FeedbackAction: Identifiable {
    public let id: String
    public let label: String
    public let style: FeedbackActionStyle
    public let dismissOnClick: Bool

    public init(id: String, label: String, style: FeedbackActionStyle = .text, dismissOnClick: Bool = true) {
        self.id = id
        self.label = label
        self.style = style
        self.dismissOnClick = dismissOnClick
    }
}

public struct UiFeedback: Identifiable {
    public let id: UInt64
    public let mode: FeedbackMode
    public let tone: FeedbackTone
    public let title: String
    public let message: String
    public let errorCode: String?
    public let diagnostic: FeedbackDiagnostic?
    public let dismissible: Bool
    public let autoDismissEnabled: Bool
    public let autoDismissMs: UInt64?
    public let modal: Bool
    public let dismissOnBackdrop: Bool
    public let actions: [FeedbackAction]

    public init(
        id: UInt64,
        mode: FeedbackMode,
        tone: FeedbackTone,
        title: String,
        message: String,
        errorCode: String? = nil,
        diagnostic: FeedbackDiagnostic? = nil,
        dismissible: Bool = true,
        autoDismissMs: UInt64? = nil,
        autoDismissEnabled: Bool = true,
        modal: Bool? = nil,
        dismissOnBackdrop: Bool = false,
        actions: [FeedbackAction] = []
    ) {
        self.id = id
        self.mode = mode
        self.tone = tone
        self.title = title
        self.message = message
        self.errorCode = errorCode
        self.diagnostic = diagnostic
        self.dismissible = dismissible
        self.autoDismissEnabled = autoDismissEnabled
        self.autoDismissMs = autoDismissEnabled ? (autoDismissMs ?? (mode == .dialog ? nil : 3_000)) : nil
        self.modal = modal ?? (mode == .dialog)
        self.dismissOnBackdrop = dismissOnBackdrop
        self.actions = actions
    }

    @MainActor
    public static func create(
        mode: FeedbackMode,
        tone: FeedbackTone,
        title: String,
        message: String,
        dismissible: Bool = true,
        autoDismissMs: UInt64? = nil,
        autoDismissEnabled: Bool = true,
        modal: Bool? = nil,
        dismissOnBackdrop: Bool = false,
        actions: [FeedbackAction] = []
    ) -> UiFeedback {
        UiFeedback(
            id: FeedbackIdentity.next(), mode: mode, tone: tone, title: title,
            message: message, dismissible: dismissible, autoDismissMs: autoDismissMs,
            autoDismissEnabled: autoDismissEnabled, modal: modal,
            dismissOnBackdrop: dismissOnBackdrop, actions: actions
        )
    }
}

private enum FeedbackIdentity {
    static var sequence: UInt64 = 0
    static func next() -> UInt64 {
        sequence += 1
        return sequence
    }
}

let classroomStatusStartAction = "start-class"
let endClassConfirmAction = "end-class-confirm"
let endClassCancelAction = "end-class-cancel"
let mediaOpenHintActionOpenMic = "open-mic"
let mediaOpenHintActionOpenCamera = "open-camera"
let mediaOpenHintActionCheckDevices = "check-devices"
let mediaOpenHintActionGotIt = "got-it"

func isMediaOpenHintAction(_ actionId: String) -> Bool {
    actionId == mediaOpenHintActionOpenMic
        || actionId == mediaOpenHintActionOpenCamera
        || actionId == mediaOpenHintActionCheckDevices
        || actionId == mediaOpenHintActionGotIt
}

@MainActor
func feedbackFromMediaOpenHint(
    audience: MediaOpenHintAudience,
    localeTag: String? = nil
) -> UiFeedback {
    let teacher = audience == .teacher
    return UiFeedback.create(
        mode: .notification,
        tone: .info,
        title: EduI18n.text(
            teacher ? "mediaOpenHintTeacherTitle" : "mediaOpenHintStudentTitle",
            localeTag: localeTag
        ),
        message: EduI18n.text(
            teacher ? "mediaOpenHintTeacherMessage" : "mediaOpenHintStudentMessage",
            localeTag: localeTag
        ),
        autoDismissEnabled: false,
        actions: teacher
            ? [
                FeedbackAction(
                    id: mediaOpenHintActionOpenMic,
                    label: EduI18n.text("mediaOpenHintOpenMic", localeTag: localeTag),
                    style: .primary
                ),
                FeedbackAction(
                    id: mediaOpenHintActionOpenCamera,
                    label: EduI18n.text("mediaOpenHintOpenCamera", localeTag: localeTag)
                ),
                FeedbackAction(
                    id: mediaOpenHintActionCheckDevices,
                    label: EduI18n.text("mediaOpenHintCheckDevices", localeTag: localeTag)
                ),
            ]
            : [
                FeedbackAction(
                    id: mediaOpenHintActionGotIt,
                    label: EduI18n.text("mediaOpenHintGotIt", localeTag: localeTag),
                    style: .primary
                ),
                FeedbackAction(
                    id: mediaOpenHintActionCheckDevices,
                    label: EduI18n.text("mediaOpenHintCheckDevices", localeTag: localeTag)
                ),
            ]
    )
}

@MainActor
func feedbackFromMediaCaptureFailure(localeTag: String? = nil) -> UiFeedback {
    UiFeedback.create(
        mode: .notification,
        tone: .warning,
        title: EduI18n.text("feedbackRtcTitle", localeTag: localeTag),
        message: EduI18n.text("mediaCaptureFailed", localeTag: localeTag),
        autoDismissEnabled: false,
        actions: [
            FeedbackAction(
                id: mediaOpenHintActionCheckDevices,
                label: EduI18n.text("mediaOpenHintCheckDevices", localeTag: localeTag),
                style: .primary
            )
        ]
    )
}

private func interactionActionLabel(
    action: String,
    localeTag: String? = nil
) -> String {
    let key: String
    switch action {
    case "start_class": key = "classroomActionStart"
    case "end_class": key = "classroomActionEnd"
    case "send_message": key = "classroomActionChat"
    case "use_microphone": key = "classroomActionMicrophone"
    case "use_camera": key = "classroomActionCamera"
    case "raise_hand": key = "classroomActionRaiseHand"
    case "manage_own_stage": key = "classroomActionOwnStage"
    case "manage_stage": key = "classroomActionStage"
    case "manage_remote_media": key = "classroomActionRemoteMedia"
    case "manage_permissions": key = "classroomActionPermissions"
    case "edit_whiteboard": key = "classroomActionWhiteboard"
    case "share_screen": key = "classroomActionScreenShare"
    default: return EduI18n.text("feedbackOperationFailed", localeTag: localeTag)
    }
    return EduI18n.text(key, localeTag: localeTag)
}

func interactionRestrictionMessage(
    action: String,
    reason: String,
    localeTag: String? = nil
) -> String {
    let messageKey: String
    switch reason {
    case "classroom_not_started": messageKey = "restrictionNotStarted"
    case "classroom_already_started": messageKey = "restrictionAlreadyStarted"
    case "classroom_ended": messageKey = "restrictionEnded"
    case "classroom_expired": messageKey = "restrictionExpired"
    case "role_not_allowed": messageKey = "restrictionRole"
    case "permission_denied": messageKey = "restrictionPermission"
    case "not_on_stage": messageKey = "restrictionNotOnStage"
    default: messageKey = "restrictionCapability"
    }
    return EduI18n.text(
        messageKey,
        ["action": interactionActionLabel(action: action, localeTag: localeTag)],
        localeTag: localeTag
    )
}

@MainActor
func interactionRestrictionFeedback(
    action: String,
    reason: String,
    localeTag: String? = nil
) -> UiFeedback {
    UiFeedback.create(
        mode: .toast,
        tone: .warning,
        title: EduI18n.text("feedbackOperationTitle", localeTag: localeTag),
        message: interactionRestrictionMessage(action: action, reason: reason, localeTag: localeTag)
    )
}

@MainActor
func permissionChangedFeedback(
    actions: [String],
    allowed: Bool,
    localeTag: String? = nil
) -> UiFeedback {
    UiFeedback.create(
        mode: .toast,
        tone: allowed ? .success : .warning,
        title: EduI18n.text("permissionChangedTitle", localeTag: localeTag),
        message: EduI18n.text(
            allowed ? "permissionChangedGranted" : "permissionChangedRevoked",
            [
                "actions": actions.joined(separator: EduI18n.text(
                    "permissionChangedSeparator",
                    localeTag: localeTag
                ))
            ],
            localeTag: localeTag
        )
    )
}

@MainActor
func feedbackFromEndClassConfirm(localeTag: String? = nil) -> UiFeedback {
    UiFeedback.create(
        mode: .dialog,
        tone: .warning,
        title: EduI18n.text("classroomEndConfirmTitle", localeTag: localeTag),
        message: EduI18n.text("classroomEndConfirmMessage", localeTag: localeTag),
        dismissible: false,
        autoDismissEnabled: false,
        modal: true,
        dismissOnBackdrop: false,
        actions: [
            FeedbackAction(
                id: endClassCancelAction,
                label: EduI18n.text("actionCancel", localeTag: localeTag),
                style: .text
            ),
            FeedbackAction(
                id: endClassConfirmAction,
                label: EduI18n.text("classroomEndConfirmAction", localeTag: localeTag),
                style: .danger
            ),
        ]
    )
}

@MainActor
func feedback(
    from status: ClassroomLifecycleStatus,
    canStart: Bool,
    localeTag: String? = nil
) -> UiFeedback? {
    let tone: FeedbackTone
    let titleKey: String
    let messageKey: String
    switch status {
    case .notStarted:
        (tone, titleKey, messageKey) = (.info, "statusNotStarted", "classroomNotificationNotStarted")
    case .ended:
        (tone, titleKey, messageKey) = (.success, "statusEnded", "classroomNotificationEnded")
    case .expired:
        (tone, titleKey, messageKey) = (.warning, "statusExpired", "classroomNotificationExpired")
    case .inProgress:
        return nil
    }
    return UiFeedback.create(
        mode: .notification,
        tone: tone,
        title: EduI18n.text(titleKey, localeTag: localeTag),
        message: EduI18n.text(messageKey, localeTag: localeTag),
        autoDismissEnabled: false,
        actions: canStart ? [FeedbackAction(
            id: classroomStatusStartAction,
            label: EduI18n.text("actionStartClass", localeTag: localeTag),
            style: .primary
        )] : []
    )
}

private enum DiagnosticFields {
    static let code = "code"
    static let message = "message"
    static let traceId = "traceId"
    static let traceIdAlt = "trace_id"
}

func extractErrorDiagnostic(from error: SdkError) -> FeedbackDiagnostic {
    let raw = error.message.trimmingCharacters(in: .whitespacesAndNewlines)
    let fromJson = parseJsonDiagnostic(raw)
    let fromLines = parseLineDiagnostic(raw)
    return FeedbackDiagnostic(
        code: nonEmpty(fromJson?.code) ?? nonEmpty(fromLines?.code) ?? String(error.code),
        message: sanitizeDiagnosticMessage(fromJson?.message ?? fromLines?.message),
        traceId: fromJson?.traceId ?? fromLines?.traceId
    )
}

private func parseJsonDiagnostic(_ raw: String) -> FeedbackDiagnostic? {
    guard let start = raw.firstIndex(of: "{"),
          let end = raw.lastIndex(of: "}"),
          start < end,
          let data = String(raw[start...end]).data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    let code: String
    if let number = object[DiagnosticFields.code] as? Int {
        code = String(number)
    } else {
        code = (object[DiagnosticFields.code] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    let message = (object[DiagnosticFields.message] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let traceId = nonEmpty(object[DiagnosticFields.traceId] as? String)
        ?? nonEmpty(object[DiagnosticFields.traceIdAlt] as? String)
    if code.isEmpty && message?.isEmpty != false && traceId == nil { return nil }
    return FeedbackDiagnostic(code: code, message: sanitizeDiagnosticMessage(message), traceId: traceId)
}

private func parseLineDiagnostic(_ raw: String) -> FeedbackDiagnostic? {
    let lines = raw.split(whereSeparator: \.isNewline).map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
    guard !lines.isEmpty else { return nil }
    var code: String?
    var traceId: String?
    var messageLines: [String] = []
    for line in lines {
        if line.hasPrefix("\(DiagnosticFields.code):") {
            code = String(line.dropFirst(DiagnosticFields.code.count + 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if line.hasPrefix("\(DiagnosticFields.traceId):") {
            traceId = String(line.dropFirst(DiagnosticFields.traceId.count + 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            messageLines.append(line)
        }
    }
    guard code != nil || traceId != nil else { return nil }
    return FeedbackDiagnostic(
        code: code ?? "",
        message: sanitizeDiagnosticMessage(messageLines.joined(separator: "\n")),
        traceId: traceId
    )
}

private func sanitizeDiagnosticMessage(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if trimmed.isEmpty || trimmed.hasPrefix("{") { return nil }
    return trimmed
}

private func nonEmpty(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

func userFacingSdkErrorMessage(
    _ error: SdkError,
    mode: FeedbackMode,
    localeTag: String? = nil
) -> String {
    switch mode {
    case .dialog:
        switch error.kind {
        case .networkError: return EduI18n.text("feedbackEnterNetwork", localeTag: localeTag)
        case .classroomNotFound: return EduI18n.text("feedbackEnterNotFound", localeTag: localeTag)
        default: return EduI18n.text("feedbackEnterFailed", localeTag: localeTag)
        }
    case .toast:
        if error.kind == .permissionDenied {
            return EduI18n.text("feedbackOperationDenied", localeTag: localeTag)
        }
        return EduI18n.text("feedbackOperationFailed", localeTag: localeTag)
    case .notification:
        if error.kind == .networkError {
            return EduI18n.text("feedbackEnterNetwork", localeTag: localeTag)
        }
        return EduI18n.text("feedbackServiceUnavailable", localeTag: localeTag)
    }
}

@MainActor
func feedback(from error: SdkError, duringInitialization: Bool, localeTag: String? = nil) -> UiFeedback {
    let id = FeedbackIdentity.next()
    let diagnostic = extractErrorDiagnostic(from: error)
    if duringInitialization || error.kind == .notInitialized || error.kind == .classroomNotFound {
        return UiFeedback(
            id: id, mode: .dialog, tone: .error,
            title: EduI18n.text("feedbackEnterTitle", localeTag: localeTag),
            message: userFacingSdkErrorMessage(error, mode: .dialog, localeTag: localeTag),
            errorCode: String(error.code), diagnostic: diagnostic, dismissible: false,
            actions: [FeedbackAction(
                id: "retry",
                label: EduI18n.text("feedbackRetry", localeTag: localeTag),
                style: .danger
            )]
        )
    }
    if error.kind == .permissionDenied || error.kind == .invalidState ||
        error.kind == .classroomNotStarted || error.kind == .classroomEnded ||
        error.kind == .classroomExpired {
        return UiFeedback(
            id: id, mode: .toast, tone: .warning,
            title: EduI18n.text("feedbackOperationTitle", localeTag: localeTag),
            message: userFacingSdkErrorMessage(error, mode: .toast, localeTag: localeTag),
            errorCode: String(error.code), dismissible: true
        )
    }
    return UiFeedback(
        id: id, mode: .notification, tone: .error,
        title: error.kind == .networkError
            ? EduI18n.text("feedbackNetworkTitle", localeTag: localeTag)
            : EduI18n.text("feedbackServiceTitle", localeTag: localeTag),
        message: userFacingSdkErrorMessage(error, mode: .notification, localeTag: localeTag),
        errorCode: String(error.code), dismissible: true
    )
}
