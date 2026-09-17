import Foundation

/// Public error contract; numeric prefixes are defined by schema/errors.yaml.
public enum SdkErrorCode: Int, Codable {
    case notInitialized = 10001
    case alreadyInitialized = 10002
    case invalidArgument = 10003
    case invalidState = 10004
    case classroomNotFound = 20001
    case permissionDenied = 20002
    case networkError = 20003
    case contractMismatch = 20004
    case joinAborted = 20005
    case classroomNotStarted = 20006
    case classroomEnded = 20007
    case classroomExpired = 20008
    case imProviderError = 30001
    case whiteboardProviderError = 40001
    case rtcProviderError = 50001
    case liveProviderError = 60001
    case uiResourceError = 70001
    case providerNotRegistered = 80001
    case providerError = 80002
    case notImplemented = 80003
    case `internal` = 90001

    var defaultMessage: String {
        switch self {
        case .notInitialized: return "SDK not initialized"
        case .alreadyInitialized: return "SDK already initialized"
        case .invalidArgument: return "Invalid argument"
        case .invalidState: return "Invalid state transition"
        case .classroomNotFound: return "Classroom not found"
        case .permissionDenied: return "Permission denied"
        case .networkError: return "Backend or network failure"
        case .contractMismatch: return "Backend response is missing required fields"
        case .joinAborted: return "Classroom join was aborted"
        case .classroomNotStarted: return "Classroom has not started"
        case .classroomEnded: return "Classroom has ended"
        case .classroomExpired: return "Classroom has expired"
        case .imProviderError: return "IM provider failure"
        case .whiteboardProviderError: return "Whiteboard provider failure"
        case .rtcProviderError: return "RTC provider failure"
        case .liveProviderError: return "Live provider failure"
        case .uiResourceError: return "UI resource failure"
        case .providerNotRegistered: return "Provider not registered"
        case .providerError: return "Provider failure"
        case .notImplemented: return "Feature not implemented"
        case .internal: return "Internal error"
        }
    }
}

public struct SdkError: LocalizedError, Codable {
    public let code: Int
    public let kind: SdkErrorCode
    public let message: String

    public init(code kind: SdkErrorCode, message: String) {
        self.code = kind.rawValue
        self.kind = kind
        self.message = message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? kind.defaultMessage
            : message
    }

    public var errorDescription: String? { message }
}
