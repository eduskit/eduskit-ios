import Foundation

/// Dispatch callback association only. Rust owns Room phases, retries and ACKs.
/// Closing invokes the native cancellation port before waiting for an open/step.
final class WhiteboardRoomMediaPump {
    typealias Completion = (Result<Void,Error>) -> Void
    struct Ports {
        let open: (@escaping Completion) -> Void
        let step: (@escaping Completion) -> Void
        let close: (@escaping Completion) -> Void
        let dispose: () -> Void
        let onError: (Error) -> Void
    }
    private let ports: Ports
    private let worker=DispatchQueue(label:"edusdk.whiteboard.room-pump",qos:.userInitiated)
    private let lifetime=DispatchWorkItem {}
    private let wakes:DispatchSourceUserDataAdd
    // Bounds queued callbacks as well as callbacks already held by the worker.
    private let admission=NSLock()
    private var closeWaiters=0
    private static let maxCloseWaiters=32
    private var callbacks:[Completion]=[] // worker only
    private var disposed=false
    private var started=false
    private var opened=false
    private var busy=false
    private var job:UUID?
    private var wanted=false
    private var closeJob:UUID?
    private var closeConfirmed=false
    private var settled=false
    init(ports:Ports) {
        self.ports=ports
        wakes=DispatchSource.makeUserDataAddSource(queue:worker)
        wakes.setEventHandler { [weak self] in
            guard let self,!isClosed else{return};wanted=true;run()
        }
        wakes.resume()
    }
    deinit { wakes.cancel() }
    var isClosed:Bool { lifetime.isCancelled }
    func start() { worker.async { [self] in guard !started,!isClosed else{return};started=true;run() } }
    func wake() { guard !isClosed else{return};wakes.add(data:1) }
    func close(_ completion:@escaping Completion = { _ in }) {
        // Fence producers immediately, including work queued before this marker.
        lifetime.cancel();wakes.cancel()
        admission.lock()
        let accepted=closeWaiters < Self.maxCloseWaiters
        if accepted {closeWaiters += 1}
        admission.unlock()
        guard accepted else {
            completion(.failure(NSError(domain:"EduSDK.WhiteboardMedia",code:40001,
                userInfo:[NSLocalizedDescriptionKey:"Whiteboard media close callback capacity exceeded"])));return
        }
        worker.async { [self] in
            if settled {deliver([completion],.success(()));return}
            callbacks.append(completion)
            if !disposed {disposed=true;ports.dispose()}
            beginClose()
        }
    }
    private func run() {
        guard started,!isClosed,!busy else{return}
        if !opened {
            execute(ports.open) { [self] in opened=true }
        } else if wanted {
            wanted=false;execute(ports.step) {}
        }
    }
    private func execute(_ operation:(@escaping Completion)->Void, success:@escaping()->Void) {
        busy=true;let ticket=UUID();job=ticket
        operation { [self] result in worker.async { [self] in
            guard job == ticket else{return};job=nil;busy=false
            if isClosed {finishClose();return}
            switch result {
            case .success:success();run()
            case .failure(let error):ports.onError(error);close()
            }
        }}
    }
    private func beginClose() {
        guard !closeConfirmed,closeJob == nil else{finishClose();return}
        let ticket=UUID();closeJob=ticket
        // Root close cancels a pending open/step. Waiting for busy here deadlocks.
        ports.close { [self] result in worker.async { [self] in
            guard closeJob == ticket else{return};closeJob=nil
            switch result {
            case .success:closeConfirmed=true;finishClose()
            case .failure(let error):
                ports.onError(error)
                let pending=callbacks;callbacks.removeAll();deliver(pending,result)
                // Another explicit close may retry; no autonomous retry.
            }
        }}
    }
    private func finishClose() {
        guard isClosed,closeConfirmed,!busy,!settled else{return}
        settled=true
        let pending=callbacks;callbacks.removeAll();deliver(pending,.success(()))
    }
    private func deliver(_ pending:[Completion],_ result:Result<Void,Error>) {
        admission.lock();closeWaiters -= pending.count;admission.unlock()
        pending.forEach{$0(result)}
    }
}
