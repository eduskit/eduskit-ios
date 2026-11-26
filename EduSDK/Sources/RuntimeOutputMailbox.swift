import Foundation

/// Read-only Core output. All access is serialized by EduSdk's Core queue.
final class RuntimeOutputMailbox {
    private(set) var revision: UInt64 = 0
    var events: [Event] = []
    var effects: [String] = []
    var telemetry: [String] = []
    private var backend: BackendSnapshot?
    private var room: RoomState?
    private var timer: ClassroomTimerSnapshot?
    private var policy: String?
    private var view: String?
    private var continuation: String?
    private var messages: [ImMessageSnapshot]?
    private var history: String?
    private var changes: Set<RuntimeProjectionField> = []

    func accept(_ update: MobileRuntimeUpdate) {
        // Pipeline epoch changes do not reset the Engine's patch baseline or reliable queues.
        revision = update.revision
        events.append(contentsOf: update.events)
        effects.append(contentsOf: update.hostEffects)
        telemetry.append(contentsOf: update.telemetryEffects)
        if let value = update.backendSnapshot { backend = value; changes.insert(.backend) }
        if let value = update.roomState { room = value; changes.insert(.room) }
        if let value = update.classroomTimer { timer = value; changes.insert(.timer) }
        if let value = update.interactionPolicyJson { policy = value; changes.insert(.policy) }
        if let value = update.classroomViewJson { view = value; changes.insert(.view) }
        if let value = update.continuationJson { continuation = value; changes.insert(.continuation) }
        if let value = update.imMessages { messages = value; changes.insert(.messages) }
        if let value = update.imHistoryJson { history = value; changes.insert(.history) }
    }

    var hasEventsOrSnapshot: Bool { !events.isEmpty || !changes.isEmpty }

    func takeSnapshot() throws -> CoreUiSnapshots? {
        guard !changes.isEmpty else { return nil }
        guard let backend, let room, let timer, let policy, let view, let messages, let history else {
            throw SdkError(code: .internal, message: "Runtime update omitted initial presentation projections")
        }
        let changedFields = changes
        changes.removeAll()
        return CoreUiSnapshots(backend: backend, room: room, timer: timer,
            interactionPolicyJson: policy, classroomViewJson: view, continuationJson: continuation,
            imMessages: messages, imHistoryJson: history, revision: revision, changedFields: changedFields)
    }
}

enum RuntimeProjectionField: Hashable { case backend, room, timer, policy, view, continuation, messages, history }

struct CoreUiSnapshots {
    let backend: BackendSnapshot
    let room: RoomState
    let timer: ClassroomTimerSnapshot
    let interactionPolicyJson: String
    let classroomViewJson: String
    let continuationJson: String?
    let imMessages: [ImMessageSnapshot]
    let imHistoryJson: String
    let revision: UInt64
    let changedFields: Set<RuntimeProjectionField>
}
