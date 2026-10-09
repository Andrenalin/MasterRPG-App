// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Network
import Testing

@testable import GameRPG

/// CODE_AUDIT_21 §6.6: nothing bounded how many advertised services the browser tracked.
@Suite("Browser service limits")
@MainActor
struct BrowserManagerLimitTests {
    private func services(_ range: Range<Int>) -> [BrowserManager.DiscoveredService] {
        range.map { BrowserManager.DiscoveredService(name: "Game \($0)", txtRecord: NWTXTRecord()) }
    }

    @Test("Only the bounded number of services is tracked")
    func trackedServicesAreCapped() {
        let browser = BrowserManager()

        browser.updateGames(from: services(0..<(BrowserManager.maximumTrackedServices + 500)))

        #expect(browser.games.count == BrowserManager.maximumTrackedServices)
        #expect(Set(browser.games.map(\.endpointName)).count == BrowserManager.maximumTrackedServices)
    }

    @Test("The removed list is bounded for a player")
    func removedServicesAreCapped() {
        let browser = BrowserManager()
        let limit = BrowserManager.maximumTrackedServices

        browser.updateGames(from: services(0..<limit))
        browser.updateGames(from: services(limit..<(2 * limit)))
        browser.updateGames(from: [])

        #expect(browser.games.isEmpty)
        #expect(browser.takeRemoved().count == limit)
        #expect(browser.takeRemoved().isEmpty)
    }

    @Test("The master's browser records no removals")
    func masterRecordsNoRemovals() {
        let browser = BrowserManager(serviceType: .master, recordsRemovals: false)

        browser.updateGames(from: services(0..<3))
        browser.updateGames(from: [])

        #expect(browser.games.isEmpty)
        #expect(browser.removed.isEmpty)
    }
}
#endif
