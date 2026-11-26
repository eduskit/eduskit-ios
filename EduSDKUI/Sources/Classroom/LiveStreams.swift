import EduSDK
import Foundation

/// 台下多路直播与台上画面复用同一套布局：一格还是那一格，只是从绑 RTC 远端视频
/// 改成挂一个直播播放器。这里把 Core 下发的流集合翻译成「哪一格放哪一路」，
/// 布局与绑定判定完全不变。
///
/// 台上（`needLive == false`）一律返回空，避免同一格既绑 RTC 又挂播放器。
public enum LiveStreams {
    /// 参与者格子 → 该用户的摄像头主流流名。屏幕共享辅流不占格子，另走主舞台。
    public static func byUser(_ snapshot: UiSnapshot) -> [String: String] {
        guard snapshot.needLive else { return [:] }
        var result: [String: String] = [:]
        for stream in snapshot.liveStreams
        where stream.streamType == LiveStreamType.main.rawValue && !stream.publisherUserId.isEmpty {
            result[stream.publisherUserId] = stream.streamName
        }
        return result
    }

    /// 全场纯音频混流。没有发布者，只能按类型找；视频路静音后靠它出声。
    public static func audioStreamName(_ snapshot: UiSnapshot) -> String? {
        guard snapshot.needLive else { return nil }
        return snapshot.liveStreams
            .first { $0.streamType == LiveStreamType.audio.rawValue }?
            .streamName
    }

    /// 某人的屏幕共享辅流。有共享时它占主舞台，主流退回条带。
    public static func auxStreamName(_ snapshot: UiSnapshot, userId: String) -> String? {
        guard snapshot.needLive else { return nil }
        return snapshot.liveStreams
            .first { $0.streamType == LiveStreamType.aux.rawValue && $0.publisherUserId == userId }?
            .streamName
    }

    /// 按流名取整条流。播放器起播需要 `url` / `muted`，不只是流名。
    public static func stream(_ snapshot: UiSnapshot, streamName: String) -> LiveStream? {
        snapshot.liveStreams.first { $0.streamName == streamName }
    }
}
