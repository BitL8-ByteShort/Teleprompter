import Foundation
import CoreGraphics
import Testing
@testable import TeleprompterCore

@Test func panelSitsCenteredBelowNotchRegardlessOfDisplayOrigin() {
    let rect = OverlayGeometry.frame(screen: CGRect(x: -1512, y: 400, width: 1512, height: 982), safeTop: 32, visibleTop: 1350, width: 460, height: 202)
    #expect(rect.midX == -756)
    #expect(rect.maxY == 1350)
    #expect(rect.width == 460)
}

@Test func panelRemainsBelowMenuBarOnScreenWithoutNotch() {
    let rect = OverlayGeometry.frame(screen: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeTop: 0, visibleTop: 1055, width: 460, height: 202)
    #expect(rect.maxY == 1055)
    #expect(rect.midX == 960)
}

@Test func panelStaysFlushBelowNotchWhenMenuBarIsHidden() {
    let rect = OverlayGeometry.frame(screen: CGRect(x: -1512, y: 400, width: 1512, height: 982), safeTop: 32, visibleTop: 1382, width: 460, height: 202)
    #expect(rect.maxY == 1350)
    #expect(rect.midX == -756)
}
