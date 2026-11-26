import Foundation
import AVFoundation
import Darwin

/// Platform audio ownership only. Completion and one-time permission come from Rust Core.
final class TeachingToolSound: NSObject, AVAudioPlayerDelegate {
    struct Poll { let generation: UUID; let startedMs: Double }
    private struct View: Decodable { let audioCues: [Cue] }
    private struct Cue: Decodable {
        let cueId: String, classroomId: String, sessionId: String
        let revision: String, authorityEpoch: String, expiresAtMonotonicMs: String
        let kind: String, validForMs: Int
    }
    private let queue = DispatchQueue(label: "edusdk.tool.audio")
    private let lock = NSLock()
    private var generation = UUID()
    private var stopped = false
    private var playbackAllowed = true
    private var players: [AVAudioPlayer] = [] // audio queue only
    private static let timebase: mach_timebase_info_data_t = {
        var value = mach_timebase_info_data_t(); mach_timebase_info(&value); return value
    }()
    private static func nowMs() -> Double {
        Double(mach_continuous_time()) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000
    }
    func capture() -> Poll {
        lock.lock(); defer { lock.unlock() }
        return Poll(generation: generation, startedMs: Self.nowMs())
    }
    func reset(final: Bool = false) {
        lock.lock(); generation = UUID(); stopped = stopped || final; lock.unlock()
        queue.async { [self] in
            for player in players { player.delegate = nil; player.stop() }
            players.removeAll()
        }
    }
    /// Called on an effect worker; native stop finishes before the receipt returns.
    func setClassroomPlaybackAllowed(_ allowed: Bool) {
        precondition(!Thread.isMainThread)
        dispatchPrecondition(condition: .notOnQueue(queue))
        lock.lock()
        playbackAllowed = allowed
        if !allowed { generation = UUID() }
        lock.unlock()
        if !allowed {
            queue.sync {
                for player in players { player.delegate = nil; player.stop() }
                players.removeAll()
            }
        }
    }

    private func permitted(_ poll: Poll, lifetime: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let elapsed = Self.nowMs() - poll.startedMs
        return !stopped && playbackAllowed && generation == poll.generation && elapsed >= 0 && elapsed < Double(lifetime)
    }
    func deliver(_ json: String, poll: Poll, claim: @escaping (String, String) -> Bool) {
        // Invoked on the SDK event worker. No JSON decoding or resource IO in SwiftUI callbacks.
        guard let data = json.data(using: .utf8), let view = try? JSONDecoder().decode(View.self, from: data) else { return }
        for cue in view.audioCues {
            guard cue.kind == "countdown_complete", !cue.cueId.isEmpty, !cue.classroomId.isEmpty,
                  !cue.sessionId.isEmpty, (1...5000).contains(cue.validForMs),
                  [cue.revision, cue.authorityEpoch, cue.expiresAtMonotonicMs].allSatisfy({ $0.range(of: "^(0|[1-9][0-9]*)$", options: .regularExpression) != nil }),
                  permitted(poll, lifetime: cue.validForMs) else { continue }
            queue.async { [self] in
                guard permitted(poll, lifetime: cue.validForMs),
                      let url = Bundle.module.url(forResource: "edusdk_tool_complete", withExtension: "wav"),
                      let player = try? AVAudioPlayer(contentsOf: url), player.prepareToPlay(),
                      permitted(poll, lifetime: cue.validForMs), claim(cue.cueId, cue.classroomId),
                      permitted(poll, lifetime: cue.validForMs) else { return }
                // Keep the host/RTC AVAudioSession configuration; this port never replaces it.
                player.delegate = self
                if permitted(poll, lifetime: cue.validForMs), player.play() { players.append(player) }
            }
        }
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        queue.async { [self] in players.removeAll { $0 === player } }
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        queue.async { [self] in players.removeAll { $0 === player } }
    }
}
