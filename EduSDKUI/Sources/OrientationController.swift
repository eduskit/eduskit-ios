import Combine
import SwiftUI

/// User-facing orientation mode.
/// - `auto`: follow system rotation
/// - `lockedPortrait` / `lockedLandscape`: hold the app in the chosen axis
public enum OrientationMode: Equatable {
    case auto
    case lockedPortrait
    case lockedLandscape
}

/// Bridges the SwiftUI layout with the hosting UIKit `EduClassroomViewController`.
/// The layout drives `mode`; the VC observes it and re-queries `supportedInterfaceOrientations`.
///
/// Not marked `@MainActor` — all mutations flow from SwiftUI / UIKit which already run on main.
public final class OrientationController: ObservableObject {
    @Published public var mode: OrientationMode = .auto

    /// Host callback: invoked whenever `mode` changes, so the VC can apply
    /// `setNeedsUpdateOfSupportedInterfaceOrientations` + `requestGeometryUpdate`.
    public var onModeChange: ((OrientationMode) -> Void)?

    public init() {}

    /// Toggle from the current *effective* orientation to its opposite (locked).
    /// A second tap when already locked returns to `.auto`.
    public func toggle(currentIsLandscape: Bool) {
        switch mode {
        case .auto:
            setMode(currentIsLandscape ? .lockedPortrait : .lockedLandscape)
        case .lockedPortrait, .lockedLandscape:
            setMode(.auto)
        }
    }

    public func setMode(_ next: OrientationMode) {
        guard mode != next else { return }
        mode = next
        onModeChange?(next)
    }
}

#if canImport(UIKit)
import UIKit

extension OrientationMode {
    var mask: UIInterfaceOrientationMask {
        switch self {
        case .auto: return .all
        case .lockedPortrait: return .portrait
        case .lockedLandscape: return [.landscapeLeft, .landscapeRight]
        }
    }

    var geometryMask: UIInterfaceOrientationMask {
        switch self {
        case .auto: return .all
        case .lockedPortrait: return .portrait
        case .lockedLandscape: return .landscapeRight
        }
    }
}
#endif
