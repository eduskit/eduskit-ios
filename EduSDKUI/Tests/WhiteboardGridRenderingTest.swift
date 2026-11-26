@testable import DrawsKit
import UIKit
import XCTest

final class WhiteboardGridRenderingTest: XCTestCase {
    @MainActor
    func testInitialBoardIsNotDroppedByTransparentRefresh() async throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
        let renderer = SharedRasterRenderer(host: host, imageCache: ImageCache(onLoaded: { _ in }))
        defer { renderer.destroy() }
        // Hold the worker to reproduce consecutive bootstrap frames arriving
        // before its first drain. No engine/network timing is left to chance.
        let queue = try XCTUnwrap(Mirror(reflecting: renderer).children.first {
            $0.label == "vectorRasterQueue"
        }?.value as? DispatchQueue)
        let frame: [String: Any] = [
            "render_message_schema_version": 2, "render_message_type": "snapshot",
            "version": 1,
            "viewport": ["width": 120, "height": 80, "dpr": 3,
                         "scale": 100, "offset_x": 0, "offset_y": 0],
            "layers": [], "dirty_rects": []
        ]
        var preview = frame
        preview["render_message_type"] = "transient"
        preview["layers"] = [["type": "overlay", "items": [
            ["type": "laser_pointer", "position": ["x": 50, "y": 40], "radius": 6]
        ]]]
        queue.suspend()
        renderer.prepareSharedVectorLayer(frame: frame)
        renderer.prepareSharedVectorLayer(frame: preview)
        queue.resume()
        await withCheckedContinuation { continuation in
            queue.async {
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: host.bounds.size, format: format).image {
            UIColor.white.setFill()
            $0.fill(host.bounds)
            renderer.render(in: $0.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.lifetime = .keepAlways
        add(attachment)
        let cgImage = try XCTUnwrap(image.cgImage)
        let data = try XCTUnwrap(cgImage.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        let dot = 60 * cgImage.bytesPerRow + 60 * 4
        let blank = 75 * cgImage.bytesPerRow + 75 * 4
        XCTAssertLessThan(Int(bytes[dot]), Int(bytes[blank]) - 10,
                          "the first committed grid must survive a later transparent refresh")
        let pointer = 120 * cgImage.bytesPerRow + 150 * 4
        XCTAssertLessThan(min(bytes[pointer], bytes[pointer + 1], bytes[pointer + 2]), 200,
                          "the newest transient overlay must still render after its base")
    }

    @MainActor
    func testCommittedGridSurvivesTransparentPreviewAtRetinaScale() async throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
        let cache = ImageCache(onLoaded: { _ in })
        let renderer = SharedRasterRenderer(host: host, imageCache: cache)
        defer { renderer.destroy() }
        let frame: [String: Any] = [
            "render_message_schema_version": 2, "render_message_type": "snapshot",
            "version": 1,
            "viewport": ["width": 120, "height": 80, "dpr": 3,
                         "scale": 100, "offset_x": 0, "offset_y": 0],
            "layers": [], "dirty_rects": []
        ]
        renderer.prepareSharedVectorLayer(frame: frame)
        for _ in 0..<200 {
            if renderer.displayedLogicalViewport() != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(renderer.displayedLogicalViewport(), host.bounds.size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let capture = {
            UIGraphicsImageRenderer(size: host.bounds.size, format: format).image { context in
                renderer.render(in: context.cgContext)
            }
        }
        let image = capture()
        let attachment = XCTAttachment(image: image)
        attachment.lifetime = .keepAlways
        add(attachment)
        let cgImage = try XCTUnwrap(image.cgImage)
        let data = try XCTUnwrap(cgImage.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        // A 20-point scene-aligned dot must be darker than the nearby board fill.
        let dot = 60 * cgImage.bytesPerRow + 60 * 4
        let blank = 75 * cgImage.bytesPerRow + 75 * 4
        XCTAssertLessThan(Int(bytes[dot]), Int(bytes[blank]) - 10)
        var transient = frame
        transient["render_message_type"] = "transient"
        renderer.prepareSharedVectorLayer(frame: transient)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(image.pngData(), capture().pngData())

        var panned = frame
        panned["viewport"] = ["width": 120, "height": 80, "dpr": 3,
                              "scale": 100, "offset_x": 7, "offset_y": 13]
        renderer.prepareSharedVectorLayer(frame: panned)
        try await Task.sleep(nanoseconds: 100_000_000)
        let shifted = try XCTUnwrap(capture().cgImage)
        let shiftedData = try XCTUnwrap(shifted.dataProvider?.data)
        let shiftedBytes = try XCTUnwrap(CFDataGetBytePtr(shiftedData))
        let shiftedDot = 99 * shifted.bytesPerRow + 81 * 4
        let shiftedBlank = 114 * shifted.bytesPerRow + 96 * 4
        XCTAssertLessThan(Int(shiftedBytes[shiftedDot]), Int(shiftedBytes[shiftedBlank]) - 10,
                          "grid must follow the same top-left pan coordinates as ink")
    }
}
