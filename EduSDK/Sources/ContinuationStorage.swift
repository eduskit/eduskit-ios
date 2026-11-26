import Foundation
import CryptoKit

/// Device-local I/O only. Resolution, account scope and revisions belong to Core.
final class ContinuationStorage {
    enum StorageError: Error { case mainThread, invalidKey, invalidValue, oversized, invalidUtf8 }
    private let directory: URL?
    init(directory: URL? = nil) { self.directory = directory }

    func execute(_ action: [String: Any]) throws -> Any {
        guard !Thread.isMainThread else { throw StorageError.mainThread }
        guard let key = action["key"] as? String, key.hasPrefix("classroom-continuation/"), key.hasSuffix("/settings") else {
            throw StorageError.invalidKey
        }
        let base = try directory ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("edusdk-continuation", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var excluded = base
        var attributes = URLResourceValues()
        attributes.isExcludedFromBackup = true
        try excluded.setResourceValues(attributes)
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = base.appendingPathComponent(name).appendingPathExtension("json")
        switch action["type"] as? String {
        case "continuation_load_settings":
            let data: Data
            do { data = try Data(contentsOf: file) }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                return NSNull()
            }
            guard data.count <= 4096 else { throw StorageError.oversized }
            guard let value = String(data: data, encoding: .utf8) else { throw StorageError.invalidUtf8 }
            return value
        case "continuation_save_settings":
            guard let value = action["value"] as? String else { throw StorageError.invalidValue }
            let data = Data(value.utf8)
            guard data.count <= 4096 else { throw StorageError.oversized }
            try data.write(to: file, options: .atomic)
            return NSNull()
        default:
            throw StorageError.invalidValue
        }
    }
}
