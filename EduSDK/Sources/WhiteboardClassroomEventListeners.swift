import Foundation

/// Typed callback objects only. Rust retains all classroom/readiness/recovery policy.
/// One worker preserves publication order across these related classroom channels.
final class WhiteboardClassroomEventListeners {
    let media: WhiteboardMediaEventListeners
    let joinSuccess: TypedEventListeners<JoinSuccessInfo>
    let joinProgress: TypedEventListeners<JoinProgress>
    let credentials: TypedEventListeners<WhiteboardCredentials?>
    let sync: TypedEventListeners<String>
    let liveStroke: TypedEventListeners<String>
    let syncReload: TypedEventListeners<WhiteboardSyncReloadRequest>
    let recovery: TypedEventListeners<WhiteboardRecoveryRequest>

    init(worker: DispatchQueue? = nil) {
        let worker = worker ?? DispatchQueue(label: "com.edukits.edusdk.whiteboard-classroom-callbacks", qos: .userInitiated)
        media = WhiteboardMediaEventListeners(worker: worker)
        joinSuccess = TypedEventListeners(worker: worker)
        joinProgress = TypedEventListeners(worker: worker)
        credentials = TypedEventListeners(worker: worker)
        sync = TypedEventListeners(worker: worker)
        liveStroke = TypedEventListeners(worker: worker)
        syncReload = TypedEventListeners(worker: worker)
        recovery = TypedEventListeners(worker: worker)
    }

    func close() {
        media.close()
        joinSuccess.close()
        joinProgress.close()
        credentials.close()
        sync.close()
        liveStroke.close()
        syncReload.close()
        recovery.close()
    }
}
