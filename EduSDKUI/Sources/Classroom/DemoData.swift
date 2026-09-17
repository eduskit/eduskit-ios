import Foundation

public struct DemoDocument {
    public var fileName: String
    public var currentPage: Int
    public var totalPages: Int
    public var zoomPercent: Int
}

public struct DemoMeetingMeta {
    public let title: String
    public let roomLabel: String
    public let coverUrl: String?
    public let elapsedLabel: String
}

public struct DemoMediaDevice: Identifiable {
    public let id: String
    public let label: String
}

public enum DemoData {
    public static let meeting = DemoMeetingMeta(
        title: EduI18n.text("demoRoadmapReview"),
        roomLabel: "Nexus Meet Room 402",
        coverUrl: "https://images.unsplash.com/photo-1497366216548-37526070297c?w=96&h=96&fit=crop",
        elapsedLabel: "00:45:12"
    )

    /// 白板接入 DrawsKit 后，`currentPage/totalPages/zoomPercent` 不再驱动画布内容 ——
    /// header 展示改由 `WhiteboardHost.shared` 提供 board 序号/总数/缩放百分比。
    /// 这里保留 fileName 作为标题占位。
    public static let document = DemoDocument(
        fileName: EduI18n.text("whiteboardFallbackTitle"),
        currentPage: 1,
        totalPages: 1,
        zoomPercent: 100
    )

    public static let cameraDevices = [
        DemoMediaDevice(id: "cam-builtin", label: "FaceTime HD Camera (Built-in)"),
        DemoMediaDevice(id: "cam-logitech", label: "Logitech StreamCam"),
        DemoMediaDevice(id: "cam-obs", label: "OBS Virtual Camera"),
    ]
    public static let micDevices = [
        DemoMediaDevice(id: "mic-builtin", label: "MacBook Pro Microphone"),
        DemoMediaDevice(id: "mic-airpods", label: "AirPods Pro"),
    ]
    public static let speakerDevices = [
        DemoMediaDevice(id: "spk-builtin", label: "MacBook Pro Speakers"),
        DemoMediaDevice(id: "spk-airpods", label: "AirPods Pro"),
    ]
}
