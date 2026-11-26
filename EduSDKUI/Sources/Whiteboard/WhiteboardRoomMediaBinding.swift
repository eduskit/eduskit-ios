import Foundation
import DrawsKit
import EduSDK

/// SDK/UIView capability association. Rust owns all Room and playback policy.
final class WhiteboardRoomMediaBinding {
    private enum Contract { static let controlAction="operate_courseware" }
    private let scope=DispatchWorkItem {}
    let mediaSessionId:String
    private let sdk:EduSdk
    private let board:DrawsKit
    private let requests:WhiteboardMediaRequestPort
    private let clock:WhiteboardMediaClockSource
    private let cleanup:WhiteboardMediaCleanupPort
    private let playback:WhiteboardPlaybackPort
    private let onReady:(Bool)->Void
    private let onError:(Error)->Void
    private let onControlError:(Error)->Void
    private var unsubscribe:(()->Void)?
    private var session:DrawsKitRoomMediaSession? // Main only
    private var rootOpenStarted=false // Main only
    private lazy var pump=WhiteboardRoomMediaPump(ports:.init(open:{ [weak self] done in
        guard let self else{done(.failure(CancellationError()));return};self.open(done)
    },step:{ [weak self] done in
        guard let self else{done(.failure(CancellationError()));return};self.step(done)
    },close:{ [weak self] done in
        guard let self else{done(.success(()));return};self.closeRoot(done)
    },dispose:{ [weak self] in self?.dispose() },onError:{ [weak self] error in self?.report(error) }))
    init(sdk:EduSdk,board:DrawsKit,mediaSessionId:String,onReady:@escaping(Bool)->Void,
         onError:@escaping(Error)->Void,onControlError:@escaping(Error)->Void) throws {
        self.mediaSessionId=mediaSessionId
        self.sdk=sdk;self.board=board;self.onReady=onReady
        self.onError=onError;self.onControlError=onControlError
        requests=try WhiteboardMediaRequestPort(sdk:sdk,mediaSessionId:mediaSessionId)
        clock=try WhiteboardMediaClockSource(sdk:sdk,mediaSessionId:mediaSessionId)
        cleanup=WhiteboardMediaCleanupPort(sdk:sdk,mediaSessionId:mediaSessionId)
        playback=try WhiteboardPlaybackPort(sdk:sdk,mediaSessionId:mediaSessionId)
    }
    func start() {
        precondition(Thread.isMainThread)
        guard !scope.isCancelled else{return}
        _ = pump
        unsubscribe=sdk.onWhiteboardMediaClock{ [weak self] _ in self?.wake() }
        pump.start()
    }
    func wake() {guard !scope.isCancelled else{return};pump.wake()}
    func close(_ completion:@escaping WhiteboardRoomMediaPump.Completion = {_ in}) {
        scope.cancel();playback.close()
        // Retain the SDK, Root and independent cleanup port through the receipt.
        pump.close { [self] result in _ = self;completion(result) }
    }
    private func assertCurrent() throws {
        if scope.isCancelled || requests.isClosed || clock.isClosed {throw CancellationError()}
    }
    private func report(_ error:Error) {guard !scope.isCancelled else{return};onError(error)}
    private func options() -> DrawsKitRoomMediaSessionOptions {
        DrawsKitRoomMediaSessionOptions(request:{ [requests=self.requests] value,done in
            // Core fences ordinary work with assertCurrent; its close effects
            // may still release known leases before this transport is disposed.
            requests.request(value){done($0.mapError{$0 as Error})}
        },cleanupRequest:{ [cleanup=self.cleanup] value,done in
            cleanup.request(value,completion:done)
        },onRetired:{
            // Root's settled close callback precedes consumption below. The
            // asynchronous SDK ACK must be included in the binding receipt.
        },clockSample:{ [clock=self.clock] in try clock.clockSample() },waitForClock:{ [clock=self.clock] done in
            clock.waitNext{done($0.map{NSNull() as Any}.mapError{$0 as Error})}
        },assertCurrent:{ [weak self] in
            guard let self else{throw CancellationError()};try self.assertCurrent()
        },canControl:{ [sdk=self.sdk] in
            try sdk.getClassroomInteractionPolicy().contains{$0.action==Contract.controlAction && $0.available}
        },supportsRate:true,onReady:{ [weak self] ready in
            guard let self,!self.scope.isCancelled else{return};self.onReady(ready)
        },onControlError:{ [weak self] error in
            guard let self,!self.scope.isCancelled else{return};self.onControlError(error)
        },initialPlayback:DrawsKitRoomPlaybackPermission(requestId:"bootstrap-\(UUID().uuidString)",allowed:false))
    }
    private func open(_ done:@escaping WhiteboardRoomMediaPump.Completion) {
        _ = clock.ready { [self] result in
            do {try result.get();try self.assertCurrent()}
            catch {done(.failure(error));return}
            let options=self.options()
            // Only UIView attachment and starting the native UI-owned port are Main.
            DispatchQueue.main.async { [self] in
                guard !self.scope.isCancelled else{done(.failure(CancellationError()));return}
                self.rootOpenStarted=true
                self.board.openRoomMediaSession(options){ [self] result in
                    DispatchQueue.main.async { [self] in
                        switch result {
                        case .success(let value):
                            guard !self.scope.isCancelled else{done(.failure(CancellationError()));return}
                            self.session=value
                            self.playback.attach({ id,allowed,completion in
                                value.setPlaybackAllowed(requestId:id,allowed:allowed,completion:completion)
                            }) { [self] result in
                                guard !self.scope.isCancelled else{done(.failure(CancellationError()));return}
                                done(result)
                            }
                        case .failure(let error):done(.failure(error))
                        }
                    }
                }
            }
        }
    }
    private func step(_ done:@escaping WhiteboardRoomMediaPump.Completion) {
        DispatchQueue.main.async { [self] in
            guard !self.scope.isCancelled,let session=self.session else{done(.failure(CancellationError()));return}
            session.step{done($0.map{_ in ()})}
        }
    }
    private func closeRoot(_ done:@escaping WhiteboardRoomMediaPump.Completion) {
        DispatchQueue.main.async { [self] in
            self.session=nil
            guard self.rootOpenStarted else{self.consumeCleanup(done);return}
            self.board.closeRoomMediaSession { [self] result in
                switch result {
                case .failure(let error):done(.failure(error))
                case .success:self.consumeCleanup(done)
                }
            }
        }
    }
    private func dispose() {
        scope.cancel();playback.close();unsubscribe?();unsubscribe=nil;clock.close()
    }
    private func consumeCleanup(_ done:@escaping WhiteboardRoomMediaPump.Completion) {
        cleanup.consume { [self] result in
            switch result {
            case .failure(let error):done(.failure(error))
            case .success:
                DispatchQueue.global(qos:.userInitiated).async { [self] in
                    requests.close();done(.success(()))
                }
            }
        }
    }
}
