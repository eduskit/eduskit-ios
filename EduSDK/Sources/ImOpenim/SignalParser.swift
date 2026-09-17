import Foundation
import CoreFoundation

private enum OrderingTokens {
    static let maxSafeJsonInteger: Double = 9_007_199_254_740_991
    static let maxSignedInt64Decimal = "9223372036854775807"
    static let decimalDigits = Set("0123456789")
}

enum SignalParser {
    static func parseSignalEnvelope(data: Data?) -> ClassroomImSignalEnvelope? {
        guard let data, !data.isEmpty else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return parseSignalEnvelope(obj: obj)
    }

    static func parseSignalEnvelope(string: String?) -> ClassroomImSignalEnvelope? {
        guard let string else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return parseSignalEnvelope(data: data)
    }

    static func parseSignalEnvelope(obj: [String: Any]) -> ClassroomImSignalEnvelope? {
        let type = (obj["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !type.isEmpty, isClassroomImSignalType(type) else { return nil }
        let signalId = (obj["signalId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !signalId.isEmpty else { return nil }
        var data = obj["data"] as? [String: Any] ?? [:]
        if type == ClassroomImSignalType.presence {
            guard let members = normalizePresenceMembers(data) else { return nil }
            data["members"] = members
        }
        return ClassroomImSignalEnvelope(
            v: obj["v"] as? Int,
            signalId: signalId,
            type: type,
            classroomId: obj["classroomId"] as? String,
            appId: obj["appId"] as? String,
            ts: obj["ts"] as? String,
            data: data
        )
    }

    /// presence 成员条目：水位规范化后交给 Core 判定。
    /// 任一条目非法即丢整条信封，避免只丢某个 family 反而让 Core 以为协议错误。
    static func normalizePresenceMembers(_ data: [String: Any]) -> [[String: Any]]? {
        guard let raw = data["members"] as? [Any] else { return nil }
        var members: [[String: Any]] = []
        for item in raw {
            guard var member = item as? [String: Any],
                  canonicalString(member["eduUserId"]) != nil else {
                return nil
            }
            guard member.keys.contains("orderings") else {
                members.append(member)
                continue
            }
            guard let entries = member["orderings"] as? [Any] else { return nil }
            var orderings: [[String: Any]] = []
            for entry in entries {
                guard let parsed = parsePresenceOrdering(entry) else { return nil }
                orderings.append(parsed.jsonObject)
            }
            member["orderings"] = orderings
            members.append(member)
        }
        return members
    }

    static func parsePresenceOrdering(_ raw: Any?) -> ClassroomPresenceOrdering? {
        guard let obj = raw as? [String: Any] else { return nil }
        guard let family = canonicalString(obj["family"]),
              let generation = normalizeOrderingInteger(obj["generation"]),
              let revision = normalizeOrderingInteger(obj["revision"]) else {
            return nil
        }
        return ClassroomPresenceOrdering(
            family: family,
            generation: generation,
            revision: revision
        )
    }

    private static func canonicalString(_ raw: Any?) -> String? {
        guard let value = raw as? String,
              !value.isEmpty,
              value.trimmingCharacters(in: .whitespacesAndNewlines) == value else {
            return nil
        }
        return value
    }

    private static func normalizeOrderingInteger(_ raw: Any?) -> String? {
        if let value = raw as? String {
            guard value == "0" ||
                    (!value.hasPrefix("0") && value.allSatisfy(OrderingTokens.decimalDigits.contains)),
                  value.count < OrderingTokens.maxSignedInt64Decimal.count ||
                    (value.count == OrderingTokens.maxSignedInt64Decimal.count &&
                     value <= OrderingTokens.maxSignedInt64Decimal) else {
                return nil
            }
            return value
        }
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let value = number.doubleValue
        guard value.isFinite,
              value >= 0,
              value <= OrderingTokens.maxSafeJsonInteger,
              value.rounded(.towardZero) == value else {
            return nil
        }
        return String(Int64(value))
    }
}

enum OpenImAdapterError: Error, LocalizedError {
    case invalidArgument(String)
    case notLoggedIn
    case operationFailed(code: Int32, message: String)
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let msg): return msg
        case .notLoggedIn: return "IM not logged in"
        case .operationFailed(_, let message): return message
        case .timeout(let op): return "\(op) timeout"
        }
    }

    var code: Int32? {
        switch self {
        case .operationFailed(let code, _): return code
        case .timeout: return -1
        default: return nil
        }
    }
}
