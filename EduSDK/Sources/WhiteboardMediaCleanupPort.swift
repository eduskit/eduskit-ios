import Foundation
import CoreFoundation

/// Callback association for Core-prepared cleanup results. This is deliberately
/// independent from the ordinary media port's business/session cancellation.
public final class WhiteboardMediaCleanupPort {
    public typealias Completion = (Result<Any,Error>)->Void
    public typealias Call = (String,@escaping(Result<String,Error>)->Void)->Void
    private enum Limits {
        static let waiters=32, records=8, bytes=64*1024
        static let timeoutMs=20_000
    }
    private final class Wait {
        let id=UUID(), cancelled=DispatchWorkItem {}
        let completion:Completion
        var key:String?
        var timer:DispatchSourceTimer?
        var done=false
        init(_ completion:@escaping Completion){self.completion=completion}
    }
    private struct Delivery {let leaseId:String;let result:[String:Any]?}
    public let mediaSessionId:String
    private let call:Call
    private let worker=DispatchQueue(label:"edusdk.media-cleanup",qos:.userInitiated)
    private let admission=NSLock()
    private var reservations=0
    private let lifetime=DispatchWorkItem {}
    private let publicationFinished=DispatchWorkItem {}
    var isConsumed:Bool {publicationFinished.isCancelled}
    // Worker-only OS state. All semantic results are prepared by Rust Core.
    private var pending:[UUID:Wait]=[:]
    private var cache:[String:Delivery]=[:]
    private var delivered=Set<String>()
    private var ownerEnded=false
    private var consuming=false,consumed=false
    private var consumption:[(Result<Void,Error>)->Void]=[]
    public init(mediaSessionId:String,call:@escaping Call) {
        self.mediaSessionId=mediaSessionId;self.call=call
    }
    private static func failure(_ message:String)->SdkError {
        SdkError(code:.whiteboardProviderError,message:message)
    }
    private static func key(_ value:[String:Any]) throws -> String {
        String(decoding:try JSONSerialization.data(withJSONObject:value,options:.sortedKeys),as:UTF8.self)
    }
    private static func envelope(_ json:String) throws -> [String:Any] {
        guard json.utf8.count<=Limits.bytes,
              let value=try JSONSerialization.jsonObject(with:Data(json.utf8)) as? [String:Any] else {
            throw failure("Invalid media cleanup envelope")
        }
        _ = try result(value)
        return value
    }
    private static func result(_ value:[String:Any]) throws -> Any {
        guard let ok=value["ok"] as? NSNumber,CFGetTypeID(ok)==CFBooleanGetTypeID() else {
            throw failure("Invalid media cleanup result")
        }
        if ok.boolValue {
            guard let data=value["data"] else {throw failure("Missing media cleanup data")}
            return data
        }
        guard let error=value["error"] as? [String:Any],let code=error["code"] as? Int,
              let kind=SdkErrorCode(rawValue:code),let message=error["message"] as? String,!message.isEmpty else {
            throw failure("Invalid media cleanup error")
        }
        throw SdkError(code:kind,message:message)
    }
    /// Root effect worker only. Cancellation withdraws this callback, never the
    /// Core-owned release operation or an already produced release proof.
    @discardableResult public func request(_ request:[String:Any],completion:@escaping Completion)->()->Void {
        precondition(!Thread.isMainThread)
        admission.lock()
        let admitted = !lifetime.isCancelled && reservations<Limits.waiters
        if admitted {reservations+=1}
        admission.unlock()
        guard admitted else {
            worker.async {completion(.failure(Self.failure("Media cleanup port closed or full")))};return {}
        }
        let wait=Wait(completion)
        worker.async { [self] in
            pending[wait.id]=wait
            do {
                if wait.cancelled.isCancelled {throw CancellationError()}
                wait.key=try Self.key(request)
                if let delivery=cache[wait.key!],let result=delivery.result {deliver(wait,delivery,result);return}
                if ownerEnded {throw Self.failure("Cleanup owner closed without a confirmed result")}
                let timer=DispatchSource.makeTimerSource(queue:worker);wait.timer=timer
                timer.setEventHandler { [weak self,weak wait] in
                    guard let self,let wait else{return}
                    self.finish(wait,.failure(Self.failure("Media cleanup result timed out")))
                }
                timer.schedule(deadline: .now() + .milliseconds(Limits.timeoutMs));timer.resume()
                let json=try Self.key(["operation":"retire","media_session_id":mediaSessionId,"request":request])
                call(json) { [weak self,weak wait] response in
                    guard let self,let wait else{return}
                    self.worker.async {
                        guard !wait.done else{return}
                        do {_ = try Self.envelope(try response.get())}
                        catch {self.finish(wait,.failure(error))}
                    }
                }
            } catch {finish(wait,.failure(error))}
        }
        return { [weak self,weak wait] in
            guard let self,let wait else{return};wait.cancelled.cancel()
            self.worker.async {self.finish(wait,.failure(CancellationError()))}
        }
    }
    /// Called on the SDK Core owner for each changed prepared delivery frame.
    func receive(_ json:String) {
        worker.async { [self] in
            guard !consumed else{return}
            do {
                let envelope=try Self.envelope(json)
                guard let data=envelope["data"] as? [String:Any],data["media_session_id"] as? String==mediaSessionId,
                      data["protocol_version"] as? Int==1,let records=data["deliveries"] as? [[String:Any]],records.count<=Limits.records else {
                    throw Self.failure("Invalid scoped cleanup delivery")
                }
                var next:[String:Delivery]=[:]
                for record in records {
                    guard let lease=record["lease_id"] as? String,let request=record["request"] as? [String:Any],
                          let result=record["result"] else{throw Self.failure("Incomplete cleanup delivery")}
                    let key=try Self.key(request)
                    guard next[key]==nil else{throw Self.failure("Duplicate cleanup delivery")}
                    if !(result is NSNull),!(result is [String:Any]) {throw Self.failure("Invalid prepared cleanup result")}
                    next[key]=Delivery(leaseId:lease,result:result as? [String:Any])
                }
                cache=next
                for wait in Array(pending.values) {
                    if let key=wait.key,let delivery=cache[key],let result=delivery.result {deliver(wait,delivery,result)}
                }
            } catch {
                lifetime.cancel()
                for wait in Array(pending.values){finish(wait,.failure(error))}
            }
        }
    }
    private func deliver(_ wait:Wait,_ delivery:Delivery,_ result:[String:Any]) {
        do {
            let data=try Self.result(result)
            if !wait.cancelled.isCancelled {delivered.insert(delivery.leaseId)}
            finish(wait,.success(data))
        } catch {finish(wait,.failure(error))}
    }
    private func finish(_ wait:Wait,_ result:Result<Any,Error>) {
        guard !wait.done else{return};wait.done=true
        wait.timer?.setEventHandler {};wait.timer?.cancel();wait.timer=nil;pending.removeValue(forKey:wait.id)
        admission.lock();reservations-=1;admission.unlock()
        wait.completion(wait.cancelled.isCancelled ? .failure(CancellationError()) : result)
    }
    func reject(_ error:Error) {
        lifetime.cancel()
        worker.async { [self] in for wait in Array(pending.values){finish(wait,.failure(error))} }
    }
    deinit {
        let waits=Array(pending.values)
        worker.async {
            for wait in waits where !wait.done {
                wait.done=true;wait.timer?.setEventHandler {};wait.timer?.cancel()
                wait.completion(.failure(Self.failure("Media cleanup port released")))
            }
        }
    }
    /// SDK calls this only after its Core owner is actually released. Prepared
    /// confirmed results remain readable until the native consumer retires.
    func ownerFinished() {
        worker.async { [self] in
            ownerEnded=true
            for wait in Array(pending.values) {finish(wait,.failure(Self.failure("Cleanup owner closed without a confirmed result")))}
        }
    }
    /// Invoke only after the owning whiteboard Core reports settled retirement.
    /// A released SDK owner has no remaining local ledger to ACK; this never
    /// supplies a release proof or turns a failed server cleanup into success.
    public func consume(completion:@escaping(Result<Void,Error>)->Void) {
        lifetime.cancel()
        worker.async { [self] in
            if consumed {completion(.success(()));return}
            guard pending.isEmpty else{completion(.failure(Self.failure("Cleanup consumer has pending I/O")));return}
            guard consumption.count<Limits.waiters else {completion(.failure(Self.failure("Cleanup consumption callback capacity")));return}
            consumption.append(completion)
            guard !consuming else{return};consuming=true
            acknowledgeNext()
        }
    }
    private func acknowledgeNext() {
        if ownerEnded {delivered.removeAll()}
        guard let lease=delivered.sorted().first else {
            consuming=false;consumed=true;cache.removeAll();publicationFinished.cancel()
            let callbacks=consumption;consumption.removeAll();callbacks.forEach{$0(.success(()))};return
        }
        do {
            let json=try Self.key(["operation":"acknowledge","media_session_id":mediaSessionId,"lease_id":lease])
            call(json) { [self] response in
                self.worker.async {
                    do {
                        if !self.ownerEnded {_ = try Self.envelope(try response.get())}
                        self.delivered.remove(lease);self.acknowledgeNext()
                    } catch {
                        self.consuming=false;let callbacks=self.consumption;self.consumption.removeAll();callbacks.forEach{$0(.failure(error))}
                    }
                }
            }
        } catch {
            consuming=false;let callbacks=consumption;consumption.removeAll();callbacks.forEach{$0(.failure(error))}
        }
    }
}
