import Foundation
import SQLite3

/// 遥测宿主：执行 Core 下发的 `telemetry_*` 副作用，并提供设备标识与落盘。
///
/// 与业务副作用彻底分开的原因是遥测必须完全让路：它不占用各域队列，
/// 失败只回执给 Core 让退避重试，绝不进入事件流或影响进课。
final class TelemetryHost {

    private enum Tokens {
        static let deviceIdKey = "edusdk.telemetry.device_id"
        static let platform = "ios"
        static let contentType = "application/x-ndjson"
        static let contentTypeHeader = "Content-Type"
        static let postMethod = "POST"

        /// 比业务请求短：遥测迟到没有价值，卡住队列反而有害。
        static let timeout: TimeInterval = 5
        static let okRange = 200..<300
        static let badRequest = 400
        static let unauthorized = 401
        static let forbidden = 403
        static let payloadTooLarge = 413
        static let endpointPath = "/v1/telemetry/events"

        /// 由 scripts/release-sdk.py 的 VERSION_PATTERNS 统一改写，release:check 会校验一致性。
        static let sdkVersion = "0.1.2"
    }

    private let defaults: UserDefaults
    private let outbox: TelemetryOutboxDatabase
    /// create.telemetryUrl 或 join.ingestUrl；空则沿用 Core 下发的 URL。
    var ingestEndpoint: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.outbox = TelemetryOutboxDatabase()
    }

    var platform: String { Tokens.platform }

    var sdkVersion: String { Tokens.sdkVersion }

    /// 设备标识，跨会话稳定。
    ///
    /// 设备维度是排障主入口之一（「这台设备一直进不去」），所以必须持久化。
    lazy var deviceId: String = {
        if let existing = defaults.string(forKey: Tokens.deviceIdKey), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: Tokens.deviceIdKey)
        return generated
    }()

    /// 执行一条遥测副作用；返回值作为回执 payload 交回 Core。
    func execute(_ action: [String: Any]) throws -> Any {
        switch action["type"] as? String ?? "" {
        case "telemetry_upload":
            try upload(
                url: resolveUploadUrl(action["url"] as? String ?? ""),
                headers: action["headers"] as? [[String]] ?? [],
                body: action["body"] as? String ?? ""
            )
            return NSNull()

        case "telemetry_persist":
            let key = action["key"] as? String ?? ""
            if let value = action["value"] as? String {
                try outbox.put(key: key, value: value)
            } else {
                try outbox.delete(key: key)
            }
            return NSNull()

        case "telemetry_restore":
            let prefix = action["key"] as? String ?? ""
            let values = try outbox.list(prefix: prefix)
            let data = try JSONSerialization.data(withJSONObject: values)
            return String(decoding: data, as: UTF8.self)

        default:
            return NSNull()
        }
    }

    /// create.telemetryUrl 或 join.ingestUrl 覆盖 Core 拼在 backend 上的地址。
    private func resolveUploadUrl(_ coreUrl: String) -> String {
        let configured = ingestEndpoint?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard let configured, !configured.isEmpty else { return coreUrl }
        if configured.hasSuffix(Tokens.endpointPath) { return configured }
        return configured + Tokens.endpointPath
    }

    private func upload(url: String, headers: [[String]], body: String) throws {
        guard let endpoint = URL(string: url) else {
            throw SdkError(code: .networkError, message: "invalid telemetry url")
        }
        var request = URLRequest(url: endpoint, timeoutInterval: Tokens.timeout)
        request.httpMethod = Tokens.postMethod
        request.setValue(Tokens.contentType, forHTTPHeaderField: Tokens.contentTypeHeader)
        for pair in headers where pair.count == 2 {
            request.setValue(pair[1], forHTTPHeaderField: pair[0])
        }
        request.httpBody = Data(body.utf8)

        // 同步等待：调用方已在专属遥测队列上，不会阻塞业务或主线程。
        let semaphore = DispatchSemaphore(value: 0)
        var failure: Error?
        let task = HostHttpSession.shared.dataTask(with: request) { _, response, error in
            defer { semaphore.signal() }
            if let error {
                failure = error
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if !Tokens.okRange.contains(status) {
                let code: SdkErrorCode
                if status == Tokens.unauthorized || status == Tokens.forbidden {
                    code = .permissionDenied
                } else if status == Tokens.badRequest || status == Tokens.payloadTooLarge {
                    code = .invalidArgument
                } else {
                    code = .networkError
                }
                failure = SdkError(code: code, message: "telemetry upload failed: HTTP \(status)")
            }
        }
        task.resume()
        if semaphore.wait(timeout: .now() + Tokens.timeout) == .timedOut {
            task.cancel()
            throw SdkError(code: .networkError, message: "telemetry upload timed out")
        }
        if let failure { throw failure }
    }
}

/** SQLite durable KV 端口；业务状态机、容量与重试策略全部由 Rust Core 决定。 */
private final class TelemetryOutboxDatabase {
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("edusdk-telemetry.sqlite3").path
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              sqlite3_exec(handle, "CREATE TABLE IF NOT EXISTS telemetry_outbox (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)", nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            handle = nil
            return
        }
        sqlite3_exec(handle, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(handle, "PRAGMA synchronous=FULL", nil, nil, nil)
    }

    deinit { sqlite3_close(handle) }

    func put(key: String, value: String) throws {
        let sql = "INSERT INTO telemetry_outbox(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, transient)
        sqlite3_bind_text(statement, 2, value, -1, transient)
        try stepDone(statement)
    }

    func delete(key: String) throws {
        let statement = try prepare("DELETE FROM telemetry_outbox WHERE key=?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, transient)
        try stepDone(statement)
    }

    func list(prefix: String) throws -> [String] {
        let statement = try prepare("SELECT value FROM telemetry_outbox WHERE substr(key,1,?)=? ORDER BY key")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(prefix.utf8.count))
        sqlite3_bind_text(statement, 2, prefix, -1, transient)
        var values: [String] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) { values.append(String(cString: text)) }
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw storageError("read failed") }
        return values
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        guard let handle else { throw storageError("database unavailable") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw storageError("prepare failed")
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw storageError("commit failed") }
    }

    private func storageError(_ message: String) -> SdkError {
        SdkError(code: .networkError, message: "telemetry outbox \(message)")
    }
}
