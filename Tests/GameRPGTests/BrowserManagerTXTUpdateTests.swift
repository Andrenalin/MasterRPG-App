// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Network
import Testing

@testable import GameRPG

/// A service is often reported before its TXT record resolves; the entry must pick the record
/// up later, or a restarted master never matches its waiting players' session.
@Suite("Browser TXT record updates")
@MainActor
struct BrowserManagerTXTUpdateTests {
    private func service(_ name: String, session: String? = nil) -> BrowserManager.DiscoveredService {
        var entries: [String: String] = [:]
        if let session { entries[NWTXTRecord.sessionKey] = session }
        return BrowserManager.DiscoveredService(name: name, txtRecord: NWTXTRecord(entries))
    }

    @Test("A TXT record that resolves later updates the entry and keeps its id")
    func lateTXTRecordUpdatesEntry() throws {
        let browser = BrowserManager(serviceType: .master)
        browser.updateGames(from: [service("Player")])
        let first = try #require(browser.games.first)
        #expect(first.sessionId == nil)

        browser.updateGames(from: [service("Player", session: "S1")])

        let updated = try #require(browser.games.first)
        #expect(browser.games.count == 1)
        #expect(updated.sessionId == "S1")
        #expect(updated.id == first.id)
    }

    @Test("A result without a TXT record keeps the known session")
    func missingTXTRecordKeepsSession() throws {
        let browser = BrowserManager(serviceType: .master)
        browser.updateGames(from: [service("Player", session: "S1")])

        browser.updateGames(from: [service("Player")])

        #expect(try #require(browser.games.first).sessionId == "S1")
    }

    @Test("A restarted master redials a player whose session arrived late")
    func masterRedialsAfterLateSession() async throws {
        let dialed = DialRecorder()
        let controller = MasterNetworkController(
            name: "Master",
            delegate: MasterNetworkControllerDelegateMock(),
            listenerBuilder: { _, _, _, _, _, _ in GameListenerAbstractionMock() as any ListenerManaging },
            browserConnectionBuilder: { endpoint, _, _ in
                dialed.endpoints.append(endpoint)
                return ConnectionControllableSpyingStub()
            },
            hostingSessions: HostingSessionStore(storage: InMemoryJoinCodeStorage())
        )
        controller.startStreaming(passcode: "1234")
        let browser = try #require(controller.networkModel.browserManager)
        let session = controller.networkModel.sessionId

        browser.updateGames(from: [service("Player")])
        controller.refresh(games: browser.games)
        #expect(dialed.endpoints.isEmpty, "no session yet")

        browser.updateGames(from: [service("Player", session: session)])
        controller.refresh(games: browser.games)
        #expect(dialed.endpoints.count == 1)
        controller.stopStreaming()
    }

    @MainActor
    private final class DialRecorder {
        var endpoints: [NWEndpoint] = []
    }
}
#endif
