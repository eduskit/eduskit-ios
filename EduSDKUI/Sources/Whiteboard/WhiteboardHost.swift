import Foundation
import UIKit
import DrawsKit
import EduSDK

/* ── Domain enums (与设计规格 §2/§3 对齐) ─────────────────────────────────── */

public enum WhiteboardTool: String, Equatable {
    case select, pen, highlighter, shape, text, eraser, laser, pan
}

public enum ShapeSubTool: String, Equatable {
    case rect, rectSolid, oval, ovalSolid, line, arrow
}

public enum WhiteboardLineStyle: Int, Equatable {
    case solid = 0, dash = 1, dot = 2
}

public enum BrushThinMode: Int, Equatable {
    case fixed = 0, pressure = 1
}

public enum PenAutoFittingMode: Int, Equatable {
    case smooth = 0, detect = 1
}

public enum FillStyle: Int, Equatable {
    case hachure = 0, crossHatch = 1, solid = 2, zigzag = 3
}

public enum Roughness: Int, Equatable {
    case neat = 0, natural = 1, wild = 2
}

public enum Roundness: Int, Equatable {
    case sharp = 0, round = 1
}

public enum OvalDrawMode: Int, Equatable {
    case fromStart = 0, fromCenter = 1
}

public enum EraserMode: Int, Equatable {
    case whole = 0, piece = 1
}

/* ── Style snapshots ─────────────────────────────────────────────────────── */

public struct PenStyle: Equatable {
    /// 与 DrawsKit `DEFAULT_BRUSH_COLOR` / `DEFAULT_BRUSH_THIN` 一致，不覆盖引擎默认。
    public var color: String = "#ff0000"
    public var thin: Int = 30
    public var thinMode: Int = BrushThinMode.fixed.rawValue
    public var lineStyle: Int = WhiteboardLineStyle.solid.rawValue
    public var taper: Bool = true
    public var magicPen: Bool = false
    public var autoFittingMode: Int = PenAutoFittingMode.detect.rawValue
    public init() {}
}

public struct HighlighterStyle: Equatable {
    public var color: String = "#ffff00"
    public init() {}
}

public struct ShapeStyle: Equatable {
    public var subTool: ShapeSubTool = .rect
    public var color: String = "#2563eb"
    public var thin: Int = 50
    public var lineStyle: Int = WhiteboardLineStyle.solid.rawValue
    public var fillEnabled: Bool = false
    public var fillColor: String? = nil
    public var fillStyle: Int = FillStyle.solid.rawValue
    public var roughness: Int = Roughness.natural.rawValue
    public var roundness: Int = Roundness.sharp.rawValue
    public var arrowEnd: Bool = false
    public var ovalDrawMode: Int = OvalDrawMode.fromStart.rawValue
    public init() {}
}

public struct TextStyle: Equatable {
    public var color: String = "#000000"
    public var size: Int = 320
    public var style: Int = 0
    public var fontFamily: String = "sans-serif"
    public var lineHeight: Float = 1.0
    public var sizeMode: Int = 0
    public init() {}
}

public struct EraserStyle: Equatable {
    public var size: Int = 50
    public var mode: Int = EraserMode.piece.rawValue
    public var piecewise: Bool = true
    public init() {}
}

public struct LaserStyle: Equatable {
    public var size: Int = 50
    public init() {}
}

public struct HistoryStatus: Equatable {
    public var canUndo: Bool = false
    public var canRedo: Bool = false
    public init(canUndo: Bool = false, canRedo: Bool = false) {
        self.canUndo = canUndo
        self.canRedo = canRedo
    }
}

/* ── Patches ─────────────────────────────────────────────────────────────── */

public struct PenPatch {
    public var color: String?
    public var thin: Int?
    public var thinMode: Int?
    public var lineStyle: Int?
    public var taper: Bool?
    public var magicPen: Bool?
    public var autoFittingMode: Int?
    public init(color: String? = nil, thin: Int? = nil, thinMode: Int? = nil, lineStyle: Int? = nil, taper: Bool? = nil, magicPen: Bool? = nil, autoFittingMode: Int? = nil) {
        self.color = color; self.thin = thin; self.thinMode = thinMode; self.lineStyle = lineStyle; self.taper = taper; self.magicPen = magicPen; self.autoFittingMode = autoFittingMode
    }
}

public struct HighlighterPatch {
    public var color: String?
    public init(color: String? = nil) { self.color = color }
}

public struct ShapePatch {
    public var color: String?
    public var thin: Int?
    public var lineStyle: Int?
    public var fillEnabled: Bool?
    public var fillColor: String?
    public var fillColorCleared: Bool = false
    public var fillStyle: Int?
    public var roughness: Int?
    public var roundness: Int?
    public var arrowEnd: Bool?
    public var ovalDrawMode: Int?
    public init(color: String? = nil, thin: Int? = nil, lineStyle: Int? = nil, fillEnabled: Bool? = nil, fillColor: String? = nil, fillColorCleared: Bool = false, fillStyle: Int? = nil, roughness: Int? = nil, roundness: Int? = nil, arrowEnd: Bool? = nil, ovalDrawMode: Int? = nil) {
        self.color = color; self.thin = thin; self.lineStyle = lineStyle; self.fillEnabled = fillEnabled; self.fillColor = fillColor; self.fillColorCleared = fillColorCleared; self.fillStyle = fillStyle; self.roughness = roughness; self.roundness = roundness; self.arrowEnd = arrowEnd; self.ovalDrawMode = ovalDrawMode
    }
}

public struct TextPatch {
    public var color: String?
    public var size: Int?
    public var style: Int?
    public var fontFamily: String?
    public var lineHeight: Float?
    public var sizeMode: Int?
    public init(color: String? = nil, size: Int? = nil, style: Int? = nil, fontFamily: String? = nil, lineHeight: Float? = nil, sizeMode: Int? = nil) {
        self.color = color; self.size = size; self.style = style; self.fontFamily = fontFamily; self.lineHeight = lineHeight; self.sizeMode = sizeMode
    }
}

public struct EraserPatch {
    public var size: Int?
    public var mode: Int?
    public var piecewise: Bool?
    public init(size: Int? = nil, mode: Int? = nil, piecewise: Bool? = nil) { self.size = size; self.mode = mode; self.piecewise = piecewise }
}

public struct LaserPatch {
    public var size: Int?
    public init(size: Int? = nil) { self.size = size }
}

/// UI 侧桥接单例：把 toolbar / header / panel 的白板动作转发到当前挂载的 DrawsKit，
/// 同时暴露 `@Published` observable state 供 SwiftUI 组件订阅。
///
/// - Note: DrawsKit 回调可能来自非主线程；对 `@Published` 属性的写入统一 hop 回主线程。
///         联动规则集中在此文件维护；面板组件仅负责渲染 + 派发 patch。
public final class WhiteboardHost: ObservableObject {
    public static let shared = WhiteboardHost()

    /// 预热白板 FFI。不创建会话、不带 token 进房。可在后台队列调用；幂等。
    public static func preloadNative() {
        DispatchQueue.global(qos: .utility).async {
            DrawsKit.preload()
        }
    }

    public private(set) weak var current: DrawsKit?
    /// 课堂会话级 DrawsKit：横竖屏切换时复用，离开课堂才 destroy。
    private var sessionDrawsKit: DrawsKit?
    private var sessionEventsBound = false
    /// 会话级常驻 surface：Mobile↔Landscape 只 reparent，不销毁 / 不 detach。
    private(set) var persistentSurface: DrawsKitView?
    private var readyStarted = false
    /// join 下发的白板凭证；优先于画布默认 demo 参数。
    private var joinCredentials: WhiteboardConfig?
    @Published public private(set) var localEditEnabled = false
    @Published public private(set) var localEditRestrictionReason: String?
    private var writeAuthorizer: (() -> Bool)?
    /// Room Token 过期时通知 Core 换发；由 ClassroomController 绑定。
    private var authExpiredHandler: (() -> Void)?
    private var readyHandler: ((String) -> Void)?
    private var failedHandler: ((String, String) -> Void)?
    private let syncBridge = WhiteboardSyncBridge()
    private let syncReloadQueue = DispatchQueue(label: "edusdk.whiteboard.sync-reload", qos: .userInitiated)
    /// DrawsKit 状态回读专用串行队列，保证顺序且不占主线程。
    private let stateSyncQueue = DispatchQueue(label: "edusdk.whiteboard.state-sync", qos: .userInitiated)
    private var sessionGeneration: UInt64 = 0
    private lazy var coreSyncTransport: DrawsKitImTransport = CoreWhiteboardImTransport(
        sendHandler: { [weak self] payload in self?.syncBridge.send(payload) },
        messageHandler: { [weak self] handler in self?.syncBridge.bindMessageHandler(handler) },
        destroyHandler: { [weak self] in self?.syncBridge.bindMessageHandler(nil) }
    )
    /// 是否已有 join 白板凭证（画布须等此为 true 再挂载 DrawsKit）。
    @Published public private(set) var hasJoinCredentials: Bool = false
    /// DrawsKit `ready()` 完成后为 true；白板槽位据此结束局部加载态。
    @Published public private(set) var engineReady: Bool = false
    /// ready() 失败时为 true，避免骨架屏永久停留。
    @Published public private(set) var engineFailed: Bool = false
    /// Core 进课进度的只读 UI 投影，用于白板区域局部 loading/disabled/failed。
    @Published public private(set) var joinProgress: JoinProgress = .idle

    // MARK: - Observable state

    @Published public private(set) var boardTotal: Int = 1
    @Published public private(set) var boardIndex: Int = 1
    @Published public private(set) var boardScalePercent: Int = 100

    @Published public private(set) var coursewareFileId: String = ""
    @Published public private(set) var coursewareTitle: String = ""
    @Published public private(set) var coursewarePageCount: Int = 0
    @Published public private(set) var coursewareThumbUrls: [String] = []
    @Published public private(set) var coursewareLoading: Bool = false
    @Published public private(set) var coursewareLoadMessage: String = ""

    public var hasCourseware: Bool { coursewarePageCount > 0 }

    /// 课件首页不可上一页
    public var canPrevPage: Bool { hasCourseware && boardIndex > 1 }

    /// 课件末页不可下一页
    public var canNextPage: Bool { hasCourseware && boardIndex < boardTotal }

    @Published public private(set) var tool: WhiteboardTool = .pen
    @Published public private(set) var pen: PenStyle = PenStyle()
    @Published public private(set) var highlighter: HighlighterStyle = HighlighterStyle()
    @Published public private(set) var shape: ShapeStyle = ShapeStyle()
    @Published public private(set) var text: TextStyle = TextStyle()
    @Published public private(set) var eraser: EraserStyle = EraserStyle()
    @Published public private(set) var laser: LaserStyle = LaserStyle()
    @Published public private(set) var history: HistoryStatus = HistoryStatus()
    @Published public private(set) var selection: [String] = []

    private var suppressBackend = 0
    private var pendingRecoveryRoomId: String?
    private var pendingRecoveryGeneration: Int64 = 0
    private var requestedRecoveryGeneration: Int64 = 0
    private var pendingSyncReloadSeq: Int64 = 0
    private var requestedSyncReloadSeq: Int64 = 0

    private init() {}

    /// 写入 join.whiteboard 凭证；离开课堂时由 `endSession` 清空。
    /// 若已有会话身份与凭证不一致，先拆掉引擎，等画布用新凭证重建。
    public func applyJoinCredentials(_ config: WhiteboardConfig?) {
        guard let config else {
            joinCredentials = nil
            hasJoinCredentials = false
            engineReady = false
            engineFailed = false
            destroySessionEngine()
            return
        }
        let sameSession = sessionDrawsKit?.initParams.roomId == config.roomId
            && sessionDrawsKit?.initParams.userId == config.userId
        joinCredentials = config
        hasJoinCredentials = true
        if sameSession, let existing = sessionDrawsKit {
            do {
                try existing.updateCredentials(config.token)
            } catch {
                engineFailed = true
            }
            return
        }
        engineReady = false
        engineFailed = false
        if sessionDrawsKit != nil {
            destroySessionEngine()
        }
    }

    public func bindSyncSender(
        _ sender: ((String) throws -> Void)?,
        liveStrokeSender: ((String) throws -> Void)? = nil,
        onFailure: ((Error) throws -> Void)? = nil
    ) {
        syncBridge.bindSender(sender, liveStroke: liveStrokeSender, onFailure: onFailure)
    }

    /// 共享白板写操作必须在进入 DrawsKit 前通过 Core 交互策略裁决。
    public func bindWriteAuthorizer(_ authorizer: (() -> Bool)?) {
        writeAuthorizer = authorizer
    }

    /// DrawsKit Room Token 过期后回调；离开课堂时传 nil。
    public func bindAuthExpired(_ handler: (() -> Void)?) {
        authExpiredHandler = handler
    }

    public func bindReadinessReporter(
        onReady: ((String) -> Void)?,
        onFailed: ((String, String) -> Void)?
    ) {
        readyHandler = onReady
        failedHandler = onFailed
    }

    private func authorizeWrite() -> Bool {
        writeAuthorizer?() == true
    }

    /// 生命周期与个人权限合并后的本地编辑门；远端同步和只读浏览保持可用。
    public func setLocalEditEnabled(_ enabled: Bool, restrictionReason: String? = nil) {
        localEditEnabled = enabled
        localEditRestrictionReason = enabled ? nil : restrictionReason
        (current ?? sessionDrawsKit)?.setDrawEnable(enabled)
    }

    public func receiveWhiteboardSync(_ payloadJson: String) {
        syncBridge.receiveSync(payloadJson)
    }

    /// 可从 SDK 事件线程调用；Bridge 负责解析与单次主线程投递。
    public func receiveWhiteboardLiveStroke(_ payloadJson: String) {
        syncBridge.receiveLiveStroke(payloadJson)
    }

    private func withBackend(_ block: () -> Void) {
        guard suppressBackend == 0 else { return }
        block()
    }

    func withBackendSuppressed(_ block: () -> Void) {
        suppressBackend += 1
        defer { suppressBackend -= 1 }
        block()
    }

    private func withBackendSuppressedValue<T>(_ block: () -> T) -> T {
        suppressBackend += 1
        defer { suppressBackend -= 1 }
        return block()
    }

    // MARK: - Lifecycle

    /// 取得或创建课堂会话 DrawsKit（同一 room/user 跨布局复用）。
    /// 无 join 凭证时返回 nil，禁止用 demo token 进房。
    func acquireSession(config: WhiteboardConfig) -> DrawsKit? {
        guard let effective = joinCredentials else { return nil }
        if let existing = sessionDrawsKit {
            if existing.initParams.roomId == effective.roomId,
               existing.initParams.userId == effective.userId {
                return existing
            }
            destroySessionEngine()
        }
        var drawsKitConfig: [String: Any] = [
            WhiteboardServerDefaults.configKeyEnvironment: effective.serverEnvironment,
            "ratio": WhiteboardLayoutDefaults.ratio,
            "toolType": DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_PEN,
        ]
        if let serverHost = effective.serverHost?.trimmingCharacters(in: .whitespacesAndNewlines),
           !serverHost.isEmpty {
            drawsKitConfig[WhiteboardServerDefaults.configKeyCustomServer] = [
                WhiteboardServerDefaults.configKeyServerHost: serverHost,
            ]
        }
        let drawsKit = DrawsKit(initParams: DrawsKitInitParams(
            id: effective.id,
            roomId: effective.roomId,
            appid: effective.appId,
            userId: effective.userId,
            token: effective.token,
            config: drawsKitConfig,
            imTransport: coreSyncTransport
        ))
        drawsKit.setDrawEnable(localEditEnabled)
        sessionDrawsKit = drawsKit
        return drawsKit
    }

    /// 取得会话级常驻 `DrawsKitView`（跨横竖屏布局复用同一 UIView）。
    func acquireSurface(config: WhiteboardConfig) -> DrawsKitView? {
        guard acquireSession(config: config) != nil else { return nil }
        if let surface = persistentSurface { return surface }
        let surface = DrawsKitView()
        persistentSurface = surface
        return surface
    }

    /// 把常驻 surface 绑到当前 host 容器（首次 attach；之后同 view 只 relayout）。
    func bindPersistentSurface(config: WhiteboardConfig, boardContainer: UIView) {
        guard let drawsKit = acquireSession(config: config),
              let surface = acquireSurface(config: config) else { return }
        drawsKit.attachView(surface, boardContainer: boardContainer)
        register(drawsKit)
        ensureSessionEvents(drawsKit)
        guard !readyStarted else { return }
        readyStarted = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak drawsKit] in
            guard let self, let drawsKit else { return }
            let ok = drawsKit.ready()
            if ok {
                self.syncAll(from: drawsKit)
            } else {
                NSLog("[WhiteboardHost] ready() returned false")
            }
            self.applyOnMain { host in
                host.markEngineReady(ok, boardId: drawsKit.initParams.roomId)
            }
        }
    }

    /// 布局 dismantle：仅当 surface 仍是该 host 的子视图时移出层级，**不** detach 引擎。
    func releaseSurfaceHost(_ host: UIView) {
        guard let surface = persistentSurface, surface.superview === host else { return }
        surface.removeFromSuperview()
    }

    /// 仅销毁引擎与 surface，保留 join 凭证（会话身份变更时重建用）。
    /// 可观察的引擎状态由会话入口先行重置，避免画布挂载期间同步发布 SwiftUI 状态。
    private func destroySessionEngine() {
        guard let drawsKit = sessionDrawsKit else {
            clearPersistentSurface()
            readyStarted = false
            sessionEventsBound = false
            return
        }
        sessionDrawsKit = nil
        sessionEventsBound = false
        readyStarted = false
        clearPersistentSurface()
        drawsKit.destroy()
        unregister(drawsKit)
    }

    func markEngineReady(
        _ ok: Bool,
        boardId: String? = nil,
        failureMessage: String? = nil,
        report: Bool = true
    ) {
        engineReady = ok
        engineFailed = !ok
        if ok {
            if report, let boardId, boardId == joinCredentials?.roomId { readyHandler?(boardId) }
            drainPendingSyncReload()
        } else if report {
            if let boardId, boardId == joinCredentials?.roomId {
                failedHandler?(boardId, failureMessage ?? "whiteboard initialization failed")
            }
        }
    }

    /// 课件绑定信令只负责提示追平；完整文档仍由 DrawsKit Room API 权威恢复。
    public func requestRecovery(roomId: String, generation: Int64) {
        applyOnMain { host in
            guard generation > host.requestedRecoveryGeneration, generation > host.pendingRecoveryGeneration else { return }
            host.pendingRecoveryRoomId = roomId
            host.pendingRecoveryGeneration = generation
            host.drainPendingSyncReload()
        }
    }

    public func requestSyncReload(coursewareId: String, serverSeq: Int64) {
        guard serverSeq > requestedSyncReloadSeq, serverSeq > pendingSyncReloadSeq else { return }
        pendingSyncReloadSeq = serverSeq
        NSLog("[WhiteboardHost] queue sync-reload coursewareId=%@ serverSeq=%lld", coursewareId, serverSeq)
        applyOnMain { host in host.drainPendingSyncReload() }
    }

    private func drainPendingSyncReload() {
        guard engineReady, let drawsKit = current ?? sessionDrawsKit else { return }
        let serverSeq = pendingSyncReloadSeq
        if pendingRecoveryRoomId != joinCredentials?.roomId { pendingRecoveryGeneration = 0 }
        guard serverSeq > requestedSyncReloadSeq || pendingRecoveryGeneration > requestedRecoveryGeneration else { return }
        requestedRecoveryGeneration = max(requestedRecoveryGeneration, pendingRecoveryGeneration)
        pendingRecoveryGeneration = 0
        pendingSyncReloadSeq = 0
        requestedSyncReloadSeq = max(requestedSyncReloadSeq, serverSeq)
        let generation = sessionGeneration
        syncReloadQueue.async { [weak self, weak drawsKit] in
            guard let self, let drawsKit else { return }
            drawsKit.syncAndReload()
            self.applyOnMain { host in
                guard host.sessionGeneration == generation else { return }
                // 状态已在入队前推进；这里只用于丢弃旧会话完成回调。
            }
        }
    }

    func updateJoinProgress(_ progress: JoinProgress) {
        joinProgress = progress
    }

    /// 离开课堂时销毁会话与常驻 surface，并清空 join 凭证。
    public func endSession() {
        sessionGeneration &+= 1
        pendingRecoveryRoomId = nil
        pendingRecoveryGeneration = 0
        requestedRecoveryGeneration = 0
        joinCredentials = nil
        hasJoinCredentials = false
        engineReady = false
        engineFailed = false
        joinProgress = .idle
        syncBridge.clear()
        pendingSyncReloadSeq = 0
        requestedSyncReloadSeq = 0
        destroySessionEngine()
    }

    private func clearPersistentSurface() {
        persistentSurface?.removeFromSuperview()
        persistentSurface = nil
    }

    /// 会话级事件只绑一次，避免横竖屏重建 Coordinator 时重复订阅。
    func ensureSessionEvents(_ drawsKit: DrawsKit) {
        guard sessionDrawsKit === drawsKit, !sessionEventsBound else { return }
        sessionEventsBound = true
        let host = self
        drawsKit.on(DrawsKit.EVENT.DK_INIT) { [weak drawsKit] _ in
            guard let drawsKit else { return }
            host.syncAll(from: drawsKit)
        }
        let boardsChanged: (Any) -> Void = { [weak drawsKit] _ in
            guard let drawsKit else { return }
            host.withBackendSuppressed { host.syncBoards(from: drawsKit) }
        }
        drawsKit.on(DrawsKit.EVENT.DK_ADDBOARD, callback: boardsChanged)
        drawsKit.on(DrawsKit.EVENT.DK_DELETEBOARD, callback: boardsChanged)
        drawsKit.on(DrawsKit.EVENT.DK_GOTOBOARD, callback: boardsChanged)
        drawsKit.on(DrawsKit.EVENT.DK_ADDTRANSCODEFILE) { [weak drawsKit] _ in
            guard let drawsKit else { return }
            host.withBackendSuppressed { host.syncCourseware(from: drawsKit) }
        }
        drawsKit.on(DrawsKit.EVENT.DK_COURSEWARE_STATUS_CHANGED) { [weak drawsKit] payload in
            guard let drawsKit else { return }
            host.applyCoursewareStatus(payload, drawsKit: drawsKit)
        }
        drawsKit.on(DrawsKit.EVENT.DK_BOARD_SCALE_CHANGE) { [weak drawsKit] _ in
            guard let drawsKit else { return }
            host.withBackendSuppressed { host.syncScale(from: drawsKit) }
        }
        drawsKit.on(DrawsKit.EVENT.DK_SELECTED_ELEMENTS) { [weak drawsKit] _ in
            guard let drawsKit else { return }
            host.withBackendSuppressed { host.syncSelection(from: drawsKit) }
        }
        drawsKit.on(DrawsKit.EVENT.DK_DRAW_STATUS_CHANGED) { [weak drawsKit] _ in
            guard let drawsKit else { return }
            host.withBackendSuppressed {
                host.syncTool(from: drawsKit)
                host.syncStyle(from: drawsKit)
            }
        }
        drawsKit.on(DrawsKit.EVENT.DK_OPERATE_CANUNDO_STATUS_CHANGED) { payload in
            host.applyHistory(canUndo: Self.boolFromPayload(payload), canRedo: nil)
        }
        drawsKit.on(DrawsKit.EVENT.DK_OPERATE_CANREDO_STATUS_CHANGED) { payload in
            host.applyHistory(canUndo: nil, canRedo: Self.boolFromPayload(payload))
        }
        drawsKit.on(DrawsKit.EVENT.DK_AUTH_EXPIRED) { _ in
            host.authExpiredHandler?()
        }
    }

    private static func boolFromPayload(_ payload: Any) -> Bool? {
        if let v = payload as? Bool { return v }
        if let n = payload as? NSNumber { return n.boolValue }
        if let arr = payload as? [Any], let first = arr.first {
            if let v = first as? Bool { return v }
            if let n = first as? NSNumber { return n.boolValue }
        }
        return nil
    }

    func register(_ drawsKit: DrawsKit) {
        current = drawsKit
        syncAll(from: drawsKit)
    }

    func unregister(_ drawsKit: DrawsKit) {
        guard current === drawsKit else { return }
        current = nil
        applyOnMain { host in
            host.boardTotal = 1
            host.boardIndex = 1
            host.boardScalePercent = 100
            host.clearCoursewareState()
            host.tool = .pen
            host.pen = PenStyle()
            host.highlighter = HighlighterStyle()
            host.shape = ShapeStyle()
            host.text = TextStyle()
            host.eraser = EraserStyle()
            host.laser = LaserStyle()
            host.history = HistoryStatus()
            host.selection = []
        }
    }

    // MARK: - Sync from DrawsKit (event-driven or one-shot)

    /// DrawsKit 侧读到的状态快照。读取与发布分离，主线程只做赋值。
    private struct BoardsSnapshot {
        let total: Int
        let index: Int
    }

    private struct CoursewareSnapshot {
        let fileId: String
        let title: String
        let pageCount: Int
        let thumbs: [String]
        let pageIndex: Int
    }

    private struct ToolSnapshot {
        let tool: WhiteboardTool
        let subTool: ShapeSubTool?
    }

    private struct StyleSnapshot {
        let pen: PenStyle
        let highlighter: HighlighterStyle
        let shape: ShapeStyle
        let text: TextStyle
        let eraser: EraserStyle
        let laser: LaserStyle
    }

    private struct DrawsKitSnapshot {
        let boards: BoardsSnapshot
        let courseware: CoursewareSnapshot?
        let scalePercent: Int
        let tool: ToolSnapshot
        let style: StyleSnapshot
        let selection: [String]
    }

    /// 一次读齐 DrawsKit 状态，再用一次主线程投递发布。
    ///
    /// 逐项 `applyOnMain` 会让 SwiftUI 在同一帧内被唤醒六次，并且 `syncBoards` 内部
    /// 还会重复读一遍课件状态；读取全部留在调用线程，主线程只做一次赋值。
    func syncAll(from drawsKit: DrawsKit) {
        let snapshot: DrawsKitSnapshot = withBackendSuppressedValue {
            DrawsKitSnapshot(
                boards: readBoards(from: drawsKit),
                courseware: readCourseware(from: drawsKit),
                scalePercent: readScale(from: drawsKit),
                tool: readTool(from: drawsKit),
                style: readStyle(from: drawsKit),
                selection: drawsKit.getSelectedElementIds()
            )
        }
        applyOnMain { host in
            host.applyBoards(snapshot.boards)
            host.applyCourseware(snapshot.courseware)
            host.boardScalePercent = snapshot.scalePercent
            host.applyTool(snapshot.tool)
            host.applyStyle(snapshot.style)
            host.selection = snapshot.selection
        }
    }

    func syncBoards(from drawsKit: DrawsKit) {
        let boards = readBoards(from: drawsKit)
        let courseware = readCourseware(from: drawsKit)
        applyOnMain { host in
            host.applyBoards(boards)
            host.applyCourseware(courseware)
        }
    }

    func syncCourseware(from drawsKit: DrawsKit) {
        let courseware = readCourseware(from: drawsKit)
        applyOnMain { host in host.applyCourseware(courseware) }
    }

    private func readBoards(from drawsKit: DrawsKit) -> BoardsSnapshot {
        let list = drawsKit.getBoardList()
        let curId = drawsKit.getCurrentBoard()
        let idx = list.firstIndex(of: curId) ?? 0
        return BoardsSnapshot(total: max(list.count, 1), index: idx + 1)
    }

    private func applyBoards(_ boards: BoardsSnapshot) {
        boardTotal = boards.total
        boardIndex = boards.index
    }

    /// 返回 nil 表示当前没有课件，发布时清空课件状态。
    private func readCourseware(from drawsKit: DrawsKit) -> CoursewareSnapshot? {
        let pageCount = drawsKit.getCoursewarePageCount()
        guard pageCount > 0 else { return nil }
        let fileId = drawsKit.getCurrentFile()
        let title: String
        if !fileId.isEmpty, let info = drawsKit.getFileInfo(fileId),
           let t = info["title"] as? String, !t.isEmpty {
            title = t
        } else {
            title = fileId
        }
        return CoursewareSnapshot(
            fileId: fileId,
            title: title,
            pageCount: pageCount,
            thumbs: fileId.isEmpty ? [] : drawsKit.getThumbnailImages(fileId),
            pageIndex: max(drawsKit.getCoursewarePageIndex() + 1, 1)
        )
    }

    private func applyCourseware(_ courseware: CoursewareSnapshot?) {
        guard let courseware else {
            clearCoursewareState()
            return
        }
        coursewareFileId = courseware.fileId
        coursewareTitle = courseware.title
        coursewarePageCount = courseware.pageCount
        if !courseware.thumbs.isEmpty || coursewareThumbUrls.isEmpty {
            coursewareThumbUrls = courseware.thumbs
        }
        boardIndex = courseware.pageIndex
        boardTotal = max(courseware.pageCount, 1)
    }

    private func clearCoursewareState() {
        coursewareFileId = ""
        coursewareTitle = ""
        coursewarePageCount = 0
        coursewareThumbUrls = []
        coursewareLoading = false
        coursewareLoadMessage = ""
    }

    private func setCoursewareLoading(_ loading: Bool, message: String = "") {
        applyOnMain { host in
            host.coursewareLoading = loading
            host.coursewareLoadMessage = message
        }
    }

    /// 解析 DK_COURSEWARE_STATUS_CHANGED：仅可见页 loading 显示遮罩；ready/error 隐藏。
    private func applyCoursewareStatus(_ payload: Any, drawsKit: DrawsKit) {
        guard let obj = Self.dictionaryFromPayload(payload) else { return }
        let status = (obj["status"] as? String) ?? ""
        let eventPage: Int
        if let n = obj["pageIndex"] as? Int {
            eventPage = n
        } else if let n = obj["pageIndex"] as? NSNumber {
            eventPage = n.intValue
        } else {
            eventPage = -1
        }
        let visiblePage = drawsKit.getCoursewarePageIndex()
        let isVisiblePage =
            eventPage < 0 || eventPage == visiblePage || (visiblePage == 0 && eventPage == 0)

        switch status {
        case CoursewareLoadStatus.loading:
            guard isVisiblePage else { return }
            setCoursewareLoading(true, message: CoursewareLoadingStrings.default)
        case CoursewareLoadStatus.ready:
            setCoursewareLoading(false)
        case CoursewareLoadStatus.error:
            let reason: String
            if let r = obj["reason"] as? String, !r.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                reason = r.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                reason = CoursewareLoadingStrings.errorFallback
            }
            NSLog("[WhiteboardHost] courseware page error: %@", reason)
            setCoursewareLoading(false, message: reason)
        default:
            break
        }
    }

    private static func dictionaryFromPayload(_ payload: Any) -> [String: Any]? {
        if let dict = payload as? [String: Any] { return dict }
        if let arr = payload as? [Any], let first = arr.first {
            return dictionaryFromPayload(first)
        }
        if let dict = payload as? NSDictionary {
            var out: [String: Any] = [:]
            for (k, v) in dict {
                if let key = k as? String { out[key] = v }
            }
            return out.isEmpty ? nil : out
        }
        return nil
    }

    func syncScale(from drawsKit: DrawsKit) {
        let clamped = readScale(from: drawsKit)
        applyOnMain { host in host.boardScalePercent = clamped }
    }

    private func readScale(from drawsKit: DrawsKit) -> Int {
        min(max(drawsKit.getBoardScale(), Self.scaleMin), Self.scaleMax)
    }

    func syncTool(from drawsKit: DrawsKit) {
        let tool = readTool(from: drawsKit)
        applyOnMain { host in host.applyTool(tool) }
    }

    private func readTool(from drawsKit: DrawsKit) -> ToolSnapshot {
        let (tool, sub) = Self.codeToTool(drawsKit.getToolType())
        return ToolSnapshot(tool: tool, subTool: sub)
    }

    private func applyTool(_ snapshot: ToolSnapshot) {
        tool = snapshot.tool
        if let sub = snapshot.subTool { shape.subTool = sub }
    }

    func syncStyle(from drawsKit: DrawsKit) {
        let style = readStyle(from: drawsKit)
        applyOnMain { host in host.applyStyle(style) }
    }

    private func applyStyle(_ style: StyleSnapshot) {
        pen = style.pen
        highlighter = style.highlighter
        shape = style.shape
        text = style.text
        eraser = style.eraser
        laser = style.laser
    }

    private func readStyle(from drawsKit: DrawsKit) -> StyleSnapshot {
        var pen = self.pen
        pen.color = drawsKit.getBrushColor()
        pen.thin = drawsKit.getBrushThin()
        pen.thinMode = drawsKit.getBrushThinMode()
        pen.lineStyle = Self.intFrom(drawsKit.getLineStyle())
        pen.taper = drawsKit.getPerfectFreehandEnable()
        pen.magicPen = drawsKit.isPenAutoFitEnable()
        pen.autoFittingMode = drawsKit.getPenAutoFittingMode()

        var highlighter = self.highlighter
        highlighter.color = drawsKit.getHighlighterColor()

        let graph = drawsKit.getGraphStyle()
        var shape = self.shape
        shape.color = Self.graphString(graph, key: "color", fallback: shape.color)
        shape.thin = Self.graphInt(graph, key: "thin", fallback: shape.thin)
        shape.fillEnabled = Self.graphBool(graph, key: "fillEnabled", fallback: shape.fillEnabled)
        shape.fillColor = Self.graphNullableString(graph, key: "fillColor", fallback: shape.fillColor)
        shape.lineStyle = Self.graphInt(graph, key: "lineStyle", fallback: shape.lineStyle)
        shape.fillStyle = Self.graphInt(graph, key: "fillStyle", fallback: shape.fillStyle)
        shape.roughness = Self.graphInt(graph, key: "roughness", fallback: shape.roughness)
        shape.roundness = Self.graphInt(graph, key: "roundness", fallback: shape.roundness)
        shape.arrowEnd = Self.graphBool(graph, key: "arrowEnd", fallback: shape.arrowEnd)
        shape.ovalDrawMode = drawsKit.getOvalDrawMode()

        var text = self.text
        text.color = drawsKit.getTextColor()
        text.size = drawsKit.getTextSize()
        text.style = drawsKit.getTextStyle()
        text.fontFamily = drawsKit.getTextFontFamily()
        text.lineHeight = drawsKit.getTextLineHeight()

        var eraser = self.eraser
        eraser.size = drawsKit.getEraserSize()
        eraser.piecewise = drawsKit.isPiecewiseErasureEnable()
        eraser.mode = eraser.piecewise ? EraserMode.piece.rawValue : EraserMode.whole.rawValue

        var laser = self.laser
        laser.size = drawsKit.getLaserSize()

        return StyleSnapshot(
            pen: pen,
            highlighter: highlighter,
            shape: shape,
            text: text,
            eraser: eraser,
            laser: laser
        )
    }

    func syncSelection(from drawsKit: DrawsKit) {
        let ids = drawsKit.getSelectedElementIds()
        applyOnMain { host in host.selection = ids }
    }

    func applyHistory(canUndo: Bool?, canRedo: Bool?) {
        applyOnMain { host in
            host.history = HistoryStatus(
                canUndo: canUndo ?? host.history.canUndo,
                canRedo: canRedo ?? host.history.canRedo
            )
        }
    }

    // MARK: - Tool commands (high-level)

    public func setTool(_ tool: WhiteboardTool) {
        self.tool = tool
        withBackend {
            guard let code = Self.toolToCode(tool, sub: shape.subTool) else { return }
            current?.setToolType(code)
        }
    }

    public func setShapeSubTool(_ sub: ShapeSubTool) {
        var updated = shape
        updated.subTool = sub

        // Linkage 2: *_solid 强制填充
        let forcedFill = sub == .rectSolid || sub == .ovalSolid
        if forcedFill && !updated.fillEnabled {
            updated.fillEnabled = true
            withBackend { current?.setGraphStyle(["fillEnabled": true]) }
        }

        // Linkage 3: 箭头 ↔ line/arrow 双向
        let isArrow = sub == .arrow
        if updated.arrowEnd != isArrow {
            updated.arrowEnd = isArrow
            withBackend { current?.setGraphStyle(["arrowEnd": isArrow]) }
        }

        shape = updated
        if tool == .shape {
            withBackend {
                guard let code = Self.toolToCode(.shape, sub: sub) else { return }
                current?.setToolType(code)
            }
        }
    }

    public func updatePen(_ patch: PenPatch) {
        var next = pen
        if let v = patch.color { next.color = v }
        if let v = patch.thin { next.thin = v }
        if let v = patch.thinMode { next.thinMode = v }
        if let v = patch.lineStyle { next.lineStyle = v }
        if let v = patch.taper { next.taper = v }
        if let v = patch.magicPen { next.magicPen = v }
        if let v = patch.autoFittingMode { next.autoFittingMode = v }

        // Linkage 1: 非实线 → 笔锋强制关闭
        if let ls = patch.lineStyle, ls != WhiteboardLineStyle.solid.rawValue, next.taper {
            next.taper = false
            withBackend { current?.setPerfectFreehandEnable(false) }
        }

        pen = next
        withBackend {
            guard let dk = current else { return }
            if let v = patch.color { dk.setBrushColor(v) }
            if let v = patch.thin { dk.setBrushThin(v) }
            if let v = patch.thinMode { dk.setBrushThinMode(v) }
            if let v = patch.lineStyle { dk.setLineStyle(v) }
            if let v = patch.taper { dk.setPerfectFreehandEnable(v) }
            if let v = patch.magicPen { dk.setPenAutoFitEnable(v) }
            if let v = patch.autoFittingMode { dk.setPenAutoFittingMode(v) }
        }
    }

    public func updateHighlighter(_ patch: HighlighterPatch) {
        if let v = patch.color { highlighter.color = v }
        withBackend {
            guard let dk = current else { return }
            if let v = patch.color { dk.setHighlighterColor(v) }
        }
    }

    public func updateShape(_ patch: ShapePatch) {
        let prev = shape
        var next = prev
        if let v = patch.color { next.color = v }
        if let v = patch.thin { next.thin = v }
        if let v = patch.lineStyle { next.lineStyle = v }
        if let v = patch.fillEnabled { next.fillEnabled = v }
        if patch.fillColorCleared { next.fillColor = nil }
        else if let v = patch.fillColor { next.fillColor = v }
        if let v = patch.fillStyle { next.fillStyle = v }
        if let v = patch.roughness { next.roughness = v }
        if let v = patch.roundness { next.roundness = v }
        if let v = patch.arrowEnd { next.arrowEnd = v }
        if let v = patch.ovalDrawMode { next.ovalDrawMode = v }

        // Linkage 3: arrowEnd toggle → 切子工具
        if let arrowEnd = patch.arrowEnd, arrowEnd != prev.arrowEnd {
            if arrowEnd && prev.subTool == .line {
                next.subTool = .arrow
                if tool == .shape, let code = Self.toolToCode(.shape, sub: .arrow) {
                    withBackend { current?.setToolType(code) }
                }
            } else if !arrowEnd && prev.subTool == .arrow {
                next.subTool = .line
                if tool == .shape, let code = Self.toolToCode(.shape, sub: .line) {
                    withBackend { current?.setToolType(code) }
                }
            }
        }

        // Linkage 2: *_solid 时禁止关闭填充
        let isSolid = next.subTool == .rectSolid || next.subTool == .ovalSolid
        if isSolid && next.fillEnabled == false {
            next.fillEnabled = true
        }

        shape = next
        withBackend {
            guard let dk = current else { return }
            var graph: [String: Any] = [:]
            if let v = patch.color { graph["color"] = v }
            if let v = patch.thin { graph["thin"] = v }
            if let v = patch.lineStyle { graph["lineStyle"] = v }
            if let v = patch.fillEnabled { graph["fillEnabled"] = v }
            if patch.fillColorCleared { graph["fillColor"] = NSNull() }
            else if let v = patch.fillColor { graph["fillColor"] = v }
            if let v = patch.fillStyle { graph["fillStyle"] = v }
            if let v = patch.roughness { graph["roughness"] = v }
            if let v = patch.roundness { graph["roundness"] = v }
            if let v = patch.arrowEnd { graph["arrowEnd"] = v }
            if !graph.isEmpty { dk.setGraphStyle(graph) }
            if let v = patch.ovalDrawMode { dk.setOvalDrawMode(v) }
        }
    }

    public func updateText(_ patch: TextPatch) {
        var next = text
        if let v = patch.color { next.color = v }
        if let v = patch.size { next.size = v }
        if let v = patch.style { next.style = v }
        if let v = patch.fontFamily { next.fontFamily = v }
        if let v = patch.lineHeight { next.lineHeight = v }
        if let v = patch.sizeMode { next.sizeMode = v }
        text = next
        withBackend {
            guard let dk = current else { return }
            if let v = patch.color { dk.setTextColor(v) }
            if let v = patch.size { dk.setTextSize(v) }
            if let v = patch.style { dk.setTextStyle(v) }
            if let v = patch.fontFamily { dk.setTextFontFamily(v) }
            if let v = patch.lineHeight { dk.setTextLineHeight(v) }
        }
    }

    public func updateEraser(_ patch: EraserPatch) {
        let prev = eraser
        var next = prev
        if let v = patch.size { next.size = v }
        if let v = patch.mode { next.mode = v }
        if let v = patch.piecewise { next.piecewise = v }

        // Linkage 4: mode ↔ piecewise 双向
        if let m = patch.mode, m != prev.mode {
            next.piecewise = m == EraserMode.piece.rawValue
        }
        if let p = patch.piecewise, p != prev.piecewise {
            next.mode = p ? EraserMode.piece.rawValue : EraserMode.whole.rawValue
        }

        eraser = next
        withBackend {
            guard let dk = current else { return }
            if let v = patch.size { dk.setEraserSize(v) }
            if next.mode != prev.mode { dk.setEraserMode(next.mode) }
            if next.piecewise != prev.piecewise { dk.setPiecewiseErasureEnable(next.piecewise) }
        }
    }

    public func updateLaser(_ patch: LaserPatch) {
        if let v = patch.size { laser.size = v }
        withBackend {
            guard let dk = current else { return }
            if let v = patch.size { dk.setLaserSize(v) }
        }
    }

    // MARK: - Global ops

    public func undo() { withBackend { current?.undo() } }
    public func redo() { withBackend { current?.redo() } }
    public func clear() { current?.clear() }

    public func copySelected() {
        withBackend {
            guard let dk = current else { return }
            let ids = dk.getSelectedElementIds()
            if !ids.isEmpty { dk.copyElementsByIds(ids) }
        }
    }

    public func deleteSelected() {
        // DrawsKit iOS 尚未暴露 deleteElements 公共接口，暂用 no-op（等 SDK 补齐）。
    }

    public func lockSelected(_ lock: Bool) {
        withBackend {
            guard let dk = current else { return }
            let ids = dk.getSelectedElementIds()
            if !ids.isEmpty {
                dk.lockElements(ids.joined(separator: ","), lock)
            }
        }
    }

    public func bringSelectedToFront() {
        // DrawsKit iOS 尚未暴露 bringToFront，暂 no-op。
    }

    public func sendSelectedToBack() {
        // DrawsKit iOS 尚未暴露 sendToBack，暂 no-op。
    }

    // MARK: - Board / zoom

    @discardableResult
    public func prevBoard() -> Bool {
        guard authorizeWrite(), suppressBackend == 0 else { return false }
        guard let dk = current else { return false }
        if dk.getCoursewarePageCount() > 0 {
            dk.prevStep()
        } else {
            dk.prevBoard()
        }
        return true
    }

    @discardableResult
    public func nextBoard() -> Bool {
        guard authorizeWrite(), suppressBackend == 0 else { return false }
        guard let dk = current else { return false }
        if dk.getCoursewarePageCount() > 0 {
            dk.nextStep()
        } else {
            dk.nextBoard()
        }
        return true
    }

    @discardableResult
    public func addBoard() -> String? {
        guard authorizeWrite() else { return nil }
        return current?.addBoard()
    }

    /// 转码 manifest（Dictionary / JSON 字符串）→ 加载课件
    @discardableResult
    public func addTranscodeFile(_ manifest: Any) -> String? {
        let fileId = current?.addTranscodeFile(manifest)
        if let dk = current, let fileId, !fileId.isEmpty {
            // 事件未到前先给反馈，避免白屏
            setCoursewareLoading(true, message: CoursewareLoadingStrings.default)
            withBackendSuppressed { syncCourseware(from: dk) }
        }
        return fileId
    }

    @discardableResult
    public func gotoBoardIndex(_ oneBasedIndex: Int) -> Bool {
        guard authorizeWrite(), suppressBackend == 0 else { return false }
        guard let dk = current else { return false }
        if dk.getCoursewarePageCount() > 0 {
            dk.gotoStep(max(oneBasedIndex - 1, 0))
            return true
        }
        let list = dk.getBoardList()
        let zero = oneBasedIndex - 1
        guard list.indices.contains(zero) else { return false }
        dk.gotoBoard(list[zero])
        return true
    }

    @discardableResult
    public func gotoStep(_ zeroBasedStep: Int) -> Bool {
        guard authorizeWrite(), suppressBackend == 0 else { return false }
        guard let dk = current else { return false }
        if dk.getCoursewarePageCount() > 0 {
            dk.gotoStep(max(zeroBasedStep, 0))
        } else {
            let list = dk.getBoardList()
            let zero = max(zeroBasedStep, 0)
            guard list.indices.contains(zero) else { return false }
            dk.gotoBoard(list[zero])
        }
        return true
    }

    public func getThumbnailImages() -> [String] {
        guard let dk = current else { return [] }
        let fileId = dk.getCurrentFile()
        guard !fileId.isEmpty else { return [] }
        return dk.getThumbnailImages(fileId)
    }

    /// 缩略图面板 `onAppear` 会调这里，而 `getThumbnailImages` 是课件读取里最贵的一步，
    /// 因此读取排到后台队列，主线程只接一次发布。
    public func refreshCourseware() {
        guard let dk = current else { return }
        stateSyncQueue.async { [weak self] in
            self?.syncCourseware(from: dk)
        }
    }

    public func zoomIn(stepPercent: Int = 10) {
        guard let dk = current else { return }
        let next = min(max(dk.getBoardScale() + stepPercent, Self.scaleMin), Self.scaleMax)
        dk.setBoardScale(next)
    }

    public func zoomOut(stepPercent: Int = 10) {
        guard let dk = current else { return }
        let next = min(max(dk.getBoardScale() - stepPercent, Self.scaleMin), Self.scaleMax)
        dk.setBoardScale(next)
    }

    public func fitZoom() {
        current?.setBoardScale(100)
    }

    public func setZoomPercent(_ percent: Int) {
        let v = min(max(percent, Self.scaleMin), Self.scaleMax)
        current?.setBoardScale(v)
    }

    // MARK: - Internal helpers

    private static func toolToCode(_ tool: WhiteboardTool, sub: ShapeSubTool) -> Int? {
        switch tool {
        case .select: return DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_MOUSE
        case .pen: return DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_PEN
        case .highlighter: return DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_HIGHLIGHTER
        case .text: return DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_TEXT
        case .eraser: return DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_ERASER
        case .laser: return DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_LASER
        case .pan: return DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_ZOOM_DRAG
        case .shape:
            switch sub {
            case .rect: return DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_RECT
            case .rectSolid: return DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_RECT_SOLID
            case .oval: return DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_OVAL
            case .ovalSolid: return DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_OVAL_SOLID
            case .line, .arrow: return DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_LINE
            }
        }
    }

    private static func codeToTool(_ code: Int) -> (WhiteboardTool, ShapeSubTool?) {
        switch code {
        case DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_MOUSE, DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_RECT_SELECT:
            return (.select, nil)
        case DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_PEN: return (.pen, nil)
        case DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_HIGHLIGHTER: return (.highlighter, nil)
        case DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_TEXT: return (.text, nil)
        case DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_ERASER: return (.eraser, nil)
        case DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_LASER: return (.laser, nil)
        case DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_ZOOM_DRAG: return (.pan, nil)
        case DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_RECT: return (.shape, .rect)
        case DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_RECT_SOLID: return (.shape, .rectSolid)
        case DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_OVAL: return (.shape, .oval)
        case DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_OVAL_SOLID: return (.shape, .ovalSolid)
        case DrawsKit.ToolType.DRAWSKIT_TOOL_TYPE_LINE: return (.shape, .line)
        default: return (.pen, nil)
        }
    }

    private static func intFrom(_ any: Any) -> Int {
        if let v = any as? Int { return v }
        if let v = any as? NSNumber { return v.intValue }
        if let v = any as? String { return Int(v) ?? 0 }
        return 0
    }

    private static func graphInt(_ graph: Any, key: String, fallback: Int) -> Int {
        guard let dict = graph as? [String: Any] ?? (graph as? NSDictionary) as? [String: Any] else { return fallback }
        if let v = dict[key] as? Int { return v }
        if let v = dict[key] as? NSNumber { return v.intValue }
        return fallback
    }

    private static func graphBool(_ graph: Any, key: String, fallback: Bool) -> Bool {
        guard let dict = graph as? [String: Any] ?? (graph as? NSDictionary) as? [String: Any] else { return fallback }
        return dict[key] as? Bool ?? fallback
    }

    private static func graphString(_ graph: Any, key: String, fallback: String) -> String {
        guard let dict = graph as? [String: Any] ?? (graph as? NSDictionary) as? [String: Any] else { return fallback }
        return dict[key] as? String ?? fallback
    }

    private static func graphNullableString(_ graph: Any, key: String, fallback: String?) -> String? {
        guard let dict = graph as? [String: Any] ?? (graph as? NSDictionary) as? [String: Any] else { return fallback }
        guard dict[key] != nil else { return fallback }
        if dict[key] is NSNull { return nil }
        return dict[key] as? String ?? fallback
    }

    /// 对 `@Published` 的写入一律异步 hop 到主队列。
    /// 若已在主线程则同步执行，会在 SwiftUI body / GeometryReader / Preference
    /// 更新期间触发 “Publishing changes from within view updates”。
    private func applyOnMain(_ block: @escaping (WhiteboardHost) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            block(self)
        }
    }

    private static let scaleMin = 10
    private static let scaleMax = 1600
}

private final class CoreWhiteboardImTransport: DrawsKitImTransport {
    private let sendHandler: (Any) -> Void
    private let messageHandler: (@escaping (Any) -> Void) -> Void
    private let destroyHandler: () -> Void

    init(
        sendHandler: @escaping (Any) -> Void,
        messageHandler: @escaping (@escaping (Any) -> Void) -> Void,
        destroyHandler: @escaping () -> Void
    ) {
        self.sendHandler = sendHandler
        self.messageHandler = messageHandler
        self.destroyHandler = destroyHandler
    }

    func send(_ payload: Any) { sendHandler(payload) }
    func onMessage(_ handler: @escaping (Any) -> Void) { messageHandler(handler) }
    func onSendAck(_ handler: @escaping (String) -> Void) {}
    func destroy() { destroyHandler() }
}
