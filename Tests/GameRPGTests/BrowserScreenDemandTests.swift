// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import GameRPG

/// The "Player" and "Join" screens share one browser, and SwiftUI can call the next screen's
/// `onAppear` before the previous screen's `onDisappear`.
@Suite("Browser screen demand")
@MainActor
struct BrowserScreenDemandTests {
    @Test("Switching screens keeps discovery running")
    func switchingScreensKeepsBrowsing() {
        let browser = BrowserManager(serviceType: .player)

        browser.screenAppeared()
        browser.screenAppeared()
        browser.screenDisappeared(keepRunning: false)

        #expect(browser.isSupervising)
        browser.stop()
    }

    @Test("Discovery stops once no screen shows it")
    func lastScreenStopsBrowsing() {
        let browser = BrowserManager(serviceType: .player)

        browser.screenAppeared()
        browser.screenDisappeared(keepRunning: false)

        #expect(!browser.isSupervising)
    }

    @Test("A connected join keeps discovery running without a screen")
    func connectedJoinKeepsBrowsing() {
        let browser = BrowserManager(serviceType: .player)

        browser.screenAppeared()
        browser.screenDisappeared(keepRunning: true)

        #expect(browser.isSupervising)
        browser.stop()
    }
}
#endif
