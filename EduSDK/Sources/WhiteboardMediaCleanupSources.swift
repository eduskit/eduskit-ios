import Foundation

/// Native delivery lifetime only. Lease validation, cleanup outcomes and ACK
/// policy stay in Core; this object never interprets the prepared JSON frame.
protocol WhiteboardMediaCleanupSource:AnyObject {
    var mediaSessionId:String {get}
    var isConsumed:Bool {get}
    func receive(_ json:String)
    func reject(_ error:Error)
    func ownerFinished()
}
extension WhiteboardMediaCleanupPort:WhiteboardMediaCleanupSource {}

/// Access only on the owning SDK Core queue, including the final publication
/// before shutdown completion and finishOwner after Core is actually released.
final class WhiteboardMediaCleanupSources {
    private struct Entry {
        weak var source:(any WhiteboardMediaCleanupSource)?
        var lastFrame:String?
    }
    private enum Limits {static let sources=8}
    private let ownerQueue:DispatchQueue
    private var entries:[Entry]=[]
    private var ownerEnded=false
    init(ownerQueue:DispatchQueue) {self.ownerQueue=ownerQueue}
    private func assertOwner() {
        dispatchPrecondition(condition:.onQueue(ownerQueue))
        precondition(!Thread.isMainThread,"cleanup publication requires Core worker")
    }
    private func prune() {entries.removeAll{$0.source==nil || $0.source?.isConsumed==true}}
    static func boundaryError(_ error:Error)->SdkError {
        if let error=error as? SdkError{return error}
        return SdkError(code:.whiteboardProviderError,message:error.localizedDescription)
    }
    func register(_ source:any WhiteboardMediaCleanupSource,read:(String)throws->String) {
        assertOwner()
        guard !ownerEnded else{source.ownerFinished();return}
        prune()
        // Registration is an OS association, not another lease reservation.
        guard !entries.contains(where:{$0.source === source}) else{return}
        guard entries.count<Limits.sources else {
            source.reject(SdkError(code:.whiteboardProviderError,message:"Native cleanup source capacity"));return
        }
        entries.append(Entry(source:source,lastFrame:nil))
        publish(read:read)
    }
    func publish(read:(String)throws->String) {
        assertOwner()
        guard !ownerEnded else{return}
        prune()
        for index in entries.indices {
            guard let source=entries[index].source else{continue}
            do {
                let data=try JSONSerialization.data(withJSONObject:["operation":"deliver","media_session_id":source.mediaSessionId])
                let frame=try read(String(decoding:data,as:UTF8.self))
                if entries[index].lastFrame != frame {
                    entries[index].lastFrame=frame;source.receive(frame)
                }
            }catch{source.reject(Self.boundaryError(error))}
        }
    }
    func finishOwner() {
        assertOwner()
        guard !ownerEnded else{return};ownerEnded=true
        entries.compactMap{$0.source}.forEach{$0.ownerFinished()}
        entries.removeAll()
    }
}
