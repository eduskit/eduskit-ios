#if canImport(UIKit)
import UIKit

/// Visible return control after the classroom view is dismissed while the session continues.
@MainActor
final class ContinuationReturnEntry {
    static let shared = ContinuationReturnEntry()
    private var window: ContinuationReturnWindow?
    private init() {}

    func hide() {
        window?.isHidden = true
        window = nil
    }

    func show(scene: UIWindowScene?, options: EduClassroomOptions) {
        guard let scene else { return }
        if window?.windowScene === scene, window?.isHidden == false { return }
        hide()
        let banner = ContinuationReturnWindow(windowScene: scene)
        banner.windowLevel = .statusBar
        banner.rootViewController = ContinuationReturnController(options: options) { [weak self] in
            self?.open(scene: scene, options: options)
        }
        banner.isHidden = false
        window = banner
    }

    private func open(scene: UIWindowScene, options: EduClassroomOptions) {
        let hostWindow = scene.windows.first { $0 !== window && !$0.isHidden && $0.rootViewController != nil }
        guard let root = hostWindow?.rootViewController else { return }
        let host = root.presentedViewController ?? root
        hide()
        EduClassroomPresenter.present(from: host, options: options)
    }
}

private enum ContinuationReturnMetrics {
    static let topInset: CGFloat = 12
    static let horizontalInset: CGFloat = 16
    static let contentInset: CGFloat = 14
    static let buttonHeight: CGFloat = 36
    static let titleFontSize: CGFloat = 15
}

private final class ContinuationReturnWindow: UIWindow {
    override var canBecomeKey: Bool { false }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === rootViewController?.view ? nil : hit
    }
}

private final class ContinuationReturnController: UIViewController {
    private let options: EduClassroomOptions
    private let onOpen: () -> Void

    init(options: EduClassroomOptions, onOpen: @escaping () -> Void) {
        self.options = options
        self.onOpen = onOpen
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let button = UIButton(type: .system)
        button.setTitle(EduI18n.text("continuationRestore"), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: ContinuationReturnMetrics.titleFontSize, weight: .semibold)
        button.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(red: 37/255, green: 43/255, blue: 50/255, alpha: 1) : .white
        }
        button.layer.cornerRadius = ContinuationReturnMetrics.buttonHeight / 2
        button.contentEdgeInsets = UIEdgeInsets(
            top: 0, left: ContinuationReturnMetrics.contentInset,
            bottom: 0, right: ContinuationReturnMetrics.contentInset
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self] _ in self?.onOpen() }, for: .touchUpInside)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: ContinuationReturnMetrics.topInset),
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.heightAnchor.constraint(equalToConstant: ContinuationReturnMetrics.buttonHeight),
            button.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: ContinuationReturnMetrics.horizontalInset),
            button.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -ContinuationReturnMetrics.horizontalInset),
        ])
    }
}
#endif
