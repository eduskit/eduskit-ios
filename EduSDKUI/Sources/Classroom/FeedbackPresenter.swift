import Foundation
import EduSDK

// Exclusively owned by EduFeedback's serial worker. Main actor never reads state.
private final class FeedbackStateBox { var value: Any? }
@MainActor public final class FeedbackPresenter {
    private let port = EduFeedback()
    private let state = FeedbackStateBox()
    private let locale: String?
    private let onFrame: (FeedbackFrame) -> Void
    private let onFailure: (Error) -> Void
    private var timer: DispatchWorkItem?
    private var closed = false
    public init(locale: String? = nil, onFrame: @escaping (FeedbackFrame) -> Void, onFailure: @escaping (Error) -> Void) {
        self.locale = locale; self.onFrame = onFrame; self.onFailure = onFailure
        let state = self.state
        port.evaluate(request: { ["operation": "create"] }, project: { object in
            let value = try feedbackValue(object)
            guard let initial = value["state"] else { throw FeedbackProjectionError.invalidResponse }
            state.value = initial
        }, completion: { result in if case .failure(let error) = result { onFailure(error) } })
    }
    public func present(_ request: FeedbackRequest) { send(request.input) }
    public func shown(_ id: UInt64) { send { ["type": "shown", "id": String(id)] } }
    public func dismiss(_ id: UInt64, reason: String = "programmatic") { send { ["type": "dismiss", "id": String(id), "reason": reason] } }
    public func action(_ id: UInt64, _ actionId: String) { send { ["type": "action", "id": String(id), "actionId": actionId] } }
    public func actionCompleted(_ id: UInt64, _ actionId: String) { send { ["type": "action_completed", "id": String(id), "actionId": actionId] } }
    public func remove(_ id: UInt64) { send { ["type": "remove", "ids": [String(id)]] } }
    public func removeGroup(_ group: String) { send { ["type": "remove_group", "group": group] } }
    private func send(_ input: @escaping () -> [String: Any]) {
        guard !closed else { return }
        let state = self.state; let locale = self.locale
        port.evaluate(request: {
            guard let state = state.value else { throw FeedbackProjectionError.invalidResponse }
            return ["operation": "reduce", "state": state, "input": input(), "nowMs": UInt64(ProcessInfo.processInfo.systemUptime * 1000)]
        }, project: { response in
            let frame = try feedbackValue(response)
            guard let value = frame["state"] else { throw FeedbackProjectionError.invalidResponse }
            state.value = value
            return try projectFeedbackFrame(frame, locale: locale)
        }, completion: { [weak self] result in
            guard let self, !self.closed else { return }
            switch result {
            case .success(let frame):
                self.timer?.cancel(); self.timer = nil
                if let delay = frame.nextWakeMs {
                    let timer = DispatchWorkItem { [weak self] in self?.send { ["type": "tick"] } }
                    self.timer = timer
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(delay)), execute: timer)
                }
                self.onFrame(frame)
            case .failure(let error): self.onFailure(error)
            }
        })
    }
    public func close() { closed = true; timer?.cancel(); timer = nil; port.invalidate() }
}
private func feedbackValue(_ response: [String: Any]) throws -> [String: Any] {
    guard response["ok"] as? Bool == true, let value = response["value"] as? [String: Any] else {
        throw NSError(domain: "EduFeedback", code: 10003, userInfo: [NSLocalizedDescriptionKey: String(describing: response["error"])])
    }
    return value
}
