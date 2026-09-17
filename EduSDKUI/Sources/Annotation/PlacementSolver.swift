import CoreGraphics
import Foundation

/// 白板设置面板放置侧（对齐 Android `PanelSide`）。
enum PanelSide {
    case right
    case left
    case above
    case below
}

/// PlacementSolver 输出（与 Android `PanelPlacement` 同构）。
struct PanelPlacement: Equatable {
    var origin: CGPoint
    var side: PanelSide
    var maxWidth: CGFloat
    var maxHeight: CGFloat
    var fitsFully: Bool
}

enum PlacementSolverDefaults {
    static let gap: CGFloat = 10
    static let edgePad: CGFloat = 12
    static let minPanelHeight: CGFloat = 160
    static let defaultPanelWidth: CGFloat = 260
    static let fallbackPanelHeight: CGFloat = 220
}

/// 确定性放置求解：优先工具列外侧水平方向，垂直对齐 `anchorY` 并 clamp 到 `safeRect`。
/// 算法与 Android `resolvePanelPlacement` 对齐。
func resolvePanelPlacement(
    toolFrame: CGRect,
    panelWidth: CGFloat,
    panelHeight: CGFloat,
    safeRect: CGRect,
    anchorY: CGFloat,
    gap: CGFloat = PlacementSolverDefaults.gap,
    minPanelHeight: CGFloat = PlacementSolverDefaults.minPanelHeight
) -> PanelPlacement? {
    let safeW = safeRect.width
    let safeH = safeRect.height
    guard safeW >= 48, safeH >= 48 else { return nil }
    guard !toolFrame.isNull, !toolFrame.isEmpty, toolFrame.width > 0, toolFrame.height > 0 else { return nil }

    let width = min(max(panelWidth, 48), safeW)
    let desiredH = max(panelHeight, 1)
    let maxH = max(min(desiredH, safeH), min(minPanelHeight, safeH))

    struct Candidate {
        let side: PanelSide
        let x: CGFloat
        let fits: Bool
        let overflow: CGFloat
    }

    let rightX = toolFrame.maxX + gap
    let leftX = toolFrame.minX - gap - width
    let rightFits = rightX + width <= safeRect.maxX + 0.5
    let leftFits = leftX >= safeRect.minX - 0.5
    let rightOverflow = max(0, rightX + width - safeRect.maxX) + max(0, safeRect.minX - rightX)
    let leftOverflow = max(0, leftX + width - safeRect.maxX) + max(0, safeRect.minX - leftX)

    let horizontal = [
        Candidate(side: .right, x: rightX, fits: rightFits, overflow: rightOverflow),
        Candidate(side: .left, x: leftX, fits: leftFits, overflow: leftOverflow),
    ]
    let bestHorizontal = horizontal.sorted { a, b in
        if a.fits != b.fits { return a.fits && !b.fits }
        return a.overflow < b.overflow
    }.first!

    let useVerticalFallback = !bestHorizontal.fits &&
        bestHorizontal.overflow > width * 0.35 &&
        (safeRect.minY < toolFrame.minY - gap - minPanelHeight ||
            safeRect.maxY > toolFrame.maxY + gap + minPanelHeight)

    let side: PanelSide
    var x: CGFloat
    var y: CGFloat
    var height = maxH

    if useVerticalFallback {
        let centerX = min(
            max(toolFrame.midX - width / 2, safeRect.minX),
            max(safeRect.minX, safeRect.maxX - width)
        )
        let aboveH = max(0, toolFrame.minY - gap - safeRect.minY)
        let belowH = max(0, safeRect.maxY - toolFrame.maxY - gap)
        if aboveH >= belowH && aboveH >= min(minPanelHeight, safeH) * 0.5 {
            side = .above
            height = max(min(desiredH, aboveH), min(minPanelHeight, aboveH))
            height = max(height, 1)
            x = centerX
            y = toolFrame.minY - gap - height
        } else if belowH > 1 {
            side = .below
            height = max(min(desiredH, belowH), min(minPanelHeight, belowH))
            height = max(height, 1)
            x = centerX
            y = toolFrame.maxY + gap
        } else {
            side = bestHorizontal.side
            x = min(max(bestHorizontal.x, safeRect.minX), max(safeRect.minX, safeRect.maxX - width))
            y = min(max(anchorY - height / 2, safeRect.minY), max(safeRect.minY, safeRect.maxY - height))
        }
    } else {
        side = bestHorizontal.side
        x = min(max(bestHorizontal.x, safeRect.minX), max(safeRect.minX, safeRect.maxX - width))
        y = min(max(anchorY - height / 2, safeRect.minY), max(safeRect.minY, safeRect.maxY - height))
    }

    y = min(max(y, safeRect.minY), max(safeRect.minY, safeRect.maxY - height))
    x = min(max(x, safeRect.minX), max(safeRect.minX, safeRect.maxX - width))

    let fitsFully = desiredH <= height + 0.5 &&
        x >= safeRect.minX - 0.5 &&
        x + width <= safeRect.maxX + 0.5 &&
        y >= safeRect.minY - 0.5 &&
        y + height <= safeRect.maxY + 0.5

    return PanelPlacement(
        origin: CGPoint(x: x, y: y),
        side: side,
        maxWidth: width,
        maxHeight: height,
        fitsFully: fitsFully
    )
}

func insetRect(_ rect: CGRect, pad: CGFloat) -> CGRect {
    guard rect.width > pad * 2, rect.height > pad * 2 else { return .null }
    return rect.insetBy(dx: pad, dy: pad)
}
