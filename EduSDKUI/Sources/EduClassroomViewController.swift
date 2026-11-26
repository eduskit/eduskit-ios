#if canImport(UIKit)
import UIKit
import SwiftUI
import EduSDK

@objc(EduClassroomViewController)
public final class EduClassroomViewController: UIViewController {
    private let options: EduClassroomOptions
    private var controller: ClassroomController!
    private var hostingController: UIHostingController<EduClassroomApp>?
    private let orientationController = OrientationController()
    private var explicitLeave = false
    private var classroomScene: UIWindowScene?

    @objc public init(options: EduClassroomOptions) {
        self.options = options
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        EduI18n.setLocale(options.localeTag)
        let chromeBackground = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(red: 8/255, green: 11/255, blue: 14/255, alpha: 1) : .white
        }
        view.backgroundColor = chromeBackground
        navigationController?.view.backgroundColor = chromeBackground
        navigationController?.setNavigationBarHidden(true, animated: false)

        let retained = ClassroomSessionRetention.take(matching: options)
        let classroomController = retained ?? ClassroomController(options: options)
        self.controller = classroomController
        if #available(iOS 15.0, *) {
            let port = IosContinuationWindowPort(
                sourceView: { [weak self] in self?.view },
                attachContent: { [weak classroomController] content, host in
                    classroomController?.attachContinuationContent(content, to: host) ?? false
                },
                onContentReleased: { [weak classroomController] in
                    classroomController?.releaseContinuationContent()
                }
            )
            classroomController.bindContinuationWindow(port, stop: { [weak port] in port?.presentationDestroyed() })
        }
        isModalInPresentation = options.continuation != nil

        // Reflect landscape lock changes into UIKit orientation machinery.
        orientationController.onModeChange = { [weak self] mode in
            guard let self else { return }
            self.applyOrientation(mode)
        }

        let root = EduClassroomApp(
            controller: classroomController,
            orientation: orientationController,
            themeMode: options.themeMode,
            localeTag: options.localeTag
        ) { [weak self] in
            self?.explicitLeave = true
            self?.dismiss(animated: true)
        } onKeepListening: { [weak self] in
            self?.explicitLeave = false
            self?.dismiss(animated: true)
        }
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = chromeBackground
        hostingController = host
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        if retained == nil { classroomController.initialize() }
    }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        orientationController.mode.mask
    }

    public override var shouldAutorotate: Bool { true }

    // MARK: - Immersive display (hide status bar / home indicator / defer system gestures)

    public override var prefersStatusBarHidden: Bool { true }

    public override var prefersHomeIndicatorAutoHidden: Bool { true }

    public override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    public override var childForStatusBarHidden: UIViewController? { nil }

    public override var childForHomeIndicatorAutoHidden: UIViewController? { nil }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let scene = view.window?.windowScene
        controller?.classroomPresentation(visible: true, scene: scene)
        classroomScene = scene
        ContinuationReturnEntry.shared.hide()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        controller?.classroomPresentation(visible: false, scene: view.window?.windowScene)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            orientationController.setMode(.auto)
            applyOrientation(.auto)
            if explicitLeave {
                ContinuationReturnEntry.shared.hide()
                controller?.destroy()
            } else if let controller {
                ClassroomSessionRetention.keep(controller)
                let continuation = controller.snapshot.continuation
                if continuation?.returnEntry == true && continuation?.playbackAllowed == true {
                    ContinuationReturnEntry.shared.show(scene: classroomScene, options: options)
                }
            }
        }
    }

    private func applyOrientation(_ mode: OrientationMode) {
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
            let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mode.geometryMask)
            view.window?.windowScene?.requestGeometryUpdate(prefs) { _ in }
        } else {
            let value: Int
            switch mode {
            case .lockedLandscape: value = UIInterfaceOrientation.landscapeRight.rawValue
            case .lockedPortrait: value = UIInterfaceOrientation.portrait.rawValue
            case .auto: value = UIInterfaceOrientation.unknown.rawValue
            }
            if value != UIInterfaceOrientation.unknown.rawValue {
                UIDevice.current.setValue(value, forKey: "orientation")
            }
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}

/// Process-owned classroom. Dismissing the view keeps this controller until an explicit leave.
enum ClassroomSessionRetention {
    private static var held: ClassroomController?

    static func keep(_ controller: ClassroomController) { held = controller }

    static func take(matching options: EduClassroomOptions) -> ClassroomController? {
        guard let held,
              held.options.appId == options.appId,
              held.options.userId == options.userId,
              held.options.classroomId == options.classroomId else { return nil }
        self.held = nil
        return held
    }
}

@objc(EduClassroomPresenter)
public final class EduClassroomPresenter: NSObject {
    /// 预热白板 FFI。不发 join、不进房。幂等。
    @objc public static func preload() {
        WhiteboardHost.preloadNative()
    }

    @objc public static func present(from host: UIViewController, options: EduClassroomOptions) {
        let vc = EduClassroomViewController(options: options)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .fullScreen
        host.present(nav, animated: true)
    }
}
#endif
