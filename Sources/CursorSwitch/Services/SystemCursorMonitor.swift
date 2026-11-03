import AppKit
import OSLog

enum SystemCursorState: Equatable {
    case arrow, contextual, unavailable
}

@MainActor
protocol SystemCursorMonitoring: AnyObject {
    func start(handler: @escaping @MainActor (SystemCursorState) -> Void)
    func stop()
}

/// Experimental compatibility boundary: Apple plans to retire currentSystem.
/// Missing or invisible cursor artwork must never leave an invisible pointer.
@MainActor
final class SystemCursorMonitor: SystemCursorMonitoring {
    private var timer: Timer?
    private let logger = Logger(subsystem: "com.josiah.cursorswitch", category: "SystemCursor")

    func start(handler: @escaping @MainActor (SystemCursorState) -> Void) {
        stop()
        var previous: SystemCursorState?
        let arrow = NSCursor.arrow
        let arrowPixels = Self.pixels(arrow.image)
        let poll: @MainActor () -> Void = { [logger] in
            let state = Self.classify(NSCursor.currentSystem, arrow: arrow, arrowPixels: arrowPixels)
            guard state != previous else { return }
            previous = state
            logger.debug("System cursor state: \(String(describing: state), privacy: .public)")
            handler(state)
        }
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { _ in
            MainActor.assumeIsolated { poll() }
        }
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    static func classify(_ cursor: NSCursor?, arrow: NSCursor) -> SystemCursorState {
        classify(cursor, arrow: arrow, arrowPixels: pixels(arrow.image))
    }

    private static func classify(_ cursor: NSCursor?, arrow: NSCursor, arrowPixels: Data?) -> SystemCursorState {
        guard let cursor, cursor.image.size.width > 0, cursor.image.size.height > 0,
              let arrowPixels else { return .unavailable }
        guard cursor.hotSpot == arrow.hotSpot, cursor.image.size == arrow.image.size else { return .contextual }
        guard let currentPixels = pixels(cursor.image) else { return .unavailable }
        return currentPixels == arrowPixels ? .arrow : .contextual
    }

    /// Compare small canonical rasters; serializing full multi-resolution TIFFs
    /// on every poll is unnecessarily expensive and can differ by representation.
    private static func pixels(_ image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: 32, height: 48, bitsPerComponent: 8,
                                      bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 32, height: 48))
        return Data(bytes: data, count: 128 * 48)
    }
}
