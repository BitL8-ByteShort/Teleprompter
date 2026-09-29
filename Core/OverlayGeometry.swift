import Foundation
import CoreGraphics

enum OverlayGeometry {
    static func frame(screen: CGRect, safeTop: Double, visibleTop: Double, width: Double, height: Double) -> CGRect {
        let actualWidth = min(width, screen.width - 32)
        let top = min(screen.maxY - safeTop, visibleTop) - 8
        return CGRect(x: screen.midX - actualWidth / 2, y: top - height, width: actualWidth, height: height)
    }
}
