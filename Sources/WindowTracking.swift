import AppKit
import CoreGraphics

struct DesktopWindow {
    let id: CGWindowID
    let frame: CGRect
    let isDock: Bool
    let canCoverScreen: Bool
}

enum WindowTracking {
    static func snapshot(overlayIDs: Set<Int>) -> [DesktopWindow] {
        guard let rows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return rows.compactMap { row in
            guard let id = row[kCGWindowNumber as String] as? Int,
                  !overlayIDs.contains(id),
                  let owner = row[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = row[kCGWindowLayer as String] as? Int,
                  let alpha = row[kCGWindowAlpha as String] as? Double, alpha > 0.1,
                  let bounds = row[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width >= 50, rect.height >= 36 else { return nil }

            let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
            let isDock = owner == dockPID && layer == dockLevel
            guard layer == 0 || isDock else { return nil }
            return DesktopWindow(id: CGWindowID(id), frame: rect, isDock: isDock,
                                 canCoverScreen: owner != ownPID && !isDock)
        }
    }

    static func isFullscreen(_ windows: [DesktopWindow], on display: CGRect) -> Bool {
        guard let front = windows.first(where: { window in
            window.canCoverScreen && window.frame.intersects(display)
        }) else { return false }
        let rect = front.frame
        // Maximized windows usually stop below the menu bar.
        return abs(rect.minX - display.minX) <= 3 && abs(rect.maxX - display.maxX) <= 3
            && abs(rect.minY - display.minY) <= 3 && abs(rect.maxY - display.maxY) <= 3
    }

}
