// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import GameRPG

@Suite("Hosting session id")
struct HostingSessionStoreTests {
    @Test("The same code keeps the session id")
    func sameCodeKeepsSession() {
        let store = HostingSessionStore(storage: InMemoryJoinCodeStorage())

        let first = store.sessionId(forPasscode: "1234", proxy: false)
        let second = store.sessionId(forPasscode: "1234", proxy: false)

        #expect(first == second)
    }

    @Test("A different code gets a new session id")
    func differentCodeGetsNewSession() {
        let store = HostingSessionStore(storage: InMemoryJoinCodeStorage())

        let first = store.sessionId(forPasscode: "1234", proxy: false)
        let second = store.sessionId(forPasscode: "5678", proxy: false)
        let third = store.sessionId(forPasscode: "1234", proxy: false)

        #expect(first != second)
        #expect(third != first, "only the latest code's session is kept")
    }

    @Test("Proxy hosting has its own session id")
    func proxyHasOwnSession() {
        let store = HostingSessionStore(storage: InMemoryJoinCodeStorage())

        let master = store.sessionId(forPasscode: "1234", proxy: false)
        let proxy = store.sessionId(forPasscode: "1234", proxy: true)

        #expect(master != proxy)
        #expect(store.sessionId(forPasscode: "1234", proxy: false) == master)
        #expect(store.sessionId(forPasscode: "1234", proxy: true) == proxy)
    }

    @Test("An unreadable keychain still keeps the session for the app run")
    func unavailableStoreKeepsSessionForRun() {
        let storage = InMemoryJoinCodeStorage(isUnavailable: true)
        let store = HostingSessionStore(storage: storage)

        let first = store.sessionId(forPasscode: "1234", proxy: false)
        let second = store.sessionId(forPasscode: "1234", proxy: false)
        let nextLaunch = HostingSessionStore(storage: storage).sessionId(forPasscode: "1234", proxy: false)

        #expect(first == second, "ending and restarting a game in the same run")
        #expect(nextLaunch != first, "nothing was stored for the next launch")
    }

    @Test("The stored session is reused on the next launch")
    func storedSessionSurvivesLaunch() async {
        let storage = InMemoryJoinCodeStorage()

        let store = HostingSessionStore(storage: storage)
        let first = store.sessionId(forPasscode: "1234", proxy: false)
        await store.waitForStoredWrites()
        let nextLaunch = HostingSessionStore(storage: storage).sessionId(forPasscode: "1234", proxy: false)

        #expect(first == nextLaunch)
    }

    @Test("A prewarmed store reads the stored session without a later Keychain read")
    func prewarmedStoreReusesStoredSession() async {
        let storage = InMemoryJoinCodeStorage()
        let firstStore = HostingSessionStore(storage: storage)
        let first = firstStore.sessionId(forPasscode: "1234", proxy: false)
        await firstStore.waitForStoredWrites()

        let nextLaunch = HostingSessionStore(storage: storage)
        await nextLaunch.prewarm()

        #expect(nextLaunch.sessionId(forPasscode: "1234", proxy: false) == first)
        #expect(nextLaunch.sessionId(forPasscode: "5678", proxy: false) != first, "another code starts a new session")
    }
}
#endif
