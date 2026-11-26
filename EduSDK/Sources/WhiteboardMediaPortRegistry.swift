import Foundation

protocol WhiteboardMediaPortLifetime: AnyObject {
    var mediaSessionId: String { get }
    var isClosed: Bool { get }
    func close()
}
extension WhiteboardMediaRequestPort: WhiteboardMediaPortLifetime {}
extension WhiteboardMediaClockSource: WhiteboardMediaPortLifetime {}

/// Weak OS port ownership only. Scope activation/retirement comes directly from
/// existing Core whiteboard effects; this does not infer classroom/media state.
final class WhiteboardMediaPortRegistry {
    private struct Entry { weak var port: WhiteboardMediaPortLifetime? }
    private enum Defaults { static let maximumPorts = 64 }
    private let lock = NSLock()
    private var scope: String?
    private var destroyed = false
    private var entries: [Entry] = []
    deinit { entries.compactMap { $0.port }.forEach { $0.close() } }

    func register(_ port: WhiteboardMediaPortLifetime) throws {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll { $0.port == nil || $0.port?.isClosed == true }
        guard !destroyed, scope == port.mediaSessionId, !port.isClosed,
              entries.count < Defaults.maximumPorts else {
            throw SdkError(code:.invalidState,message:"Whiteboard media request port scope is not active or capacity is reached")
        }
        entries.append(Entry(port:port))
    }
    func activate(_ scope: String) {
        lock.lock()
        guard !destroyed, self.scope != scope else { lock.unlock(); return }
        self.scope = scope
        let retired = entries.compactMap { $0.port }; entries.removeAll()
        lock.unlock()
        retired.forEach { $0.close() }
    }
    func retire() { retire(final:false) }
    func destroy() { retire(final:true) }
    private func retire(final: Bool) {
        lock.lock(); destroyed = destroyed || final; scope = nil
        let retired = entries.compactMap { $0.port }; entries.removeAll()
        lock.unlock()
        retired.forEach { $0.close() }
    }
}
