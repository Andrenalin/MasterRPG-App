// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Synchronization
import Testing

@testable import GameRPG

@Suite("GameJoinCodeModel — CODE_AUDIT_Join")
@MainActor
struct GameJoinCodeModelTests {
    private static let masterKey = "MasterRPGMasterJoinCode"
    private static let playerKey = "MasterRPGPlayerJoinCode"
    private static let lastCodeKey = "MasterRPGLastUsedMasterJoinCode"
    private static let lastHostKey = "MasterRPGLastUsedMasterHost"

    @Test("Only four ASCII digits are a valid code (§5.7)")
    func validationIsAsciiOnly() {
        #expect(GameJoinCodeModel.isValidCode("4821"))
        #expect(GameJoinCodeModel.isValidCode("0007"))
        #expect(!GameJoinCodeModel.isValidCode("٤٨٢١"))
        #expect(!GameJoinCodeModel.isValidCode("４８２１"))
        #expect(!GameJoinCodeModel.isValidCode("½½½½"))
        #expect(!GameJoinCodeModel.isValidCode("482"))
        #expect(!GameJoinCodeModel.isValidCode("48211"))
    }

    @Test("Input is normalised to ASCII digits and capped (§5.7)")
    func sanitizingConvertsDigits() {
        #expect(GameJoinCodeModel.sanitized("٤٨٢١") == "4821")
        #expect(GameJoinCodeModel.sanitized("48 21x9") == "4821")
        #expect(GameJoinCodeModel.sanitized("½") == "")
        #expect(GameJoinCodeModel.sanitized("") == "")
    }

    @Test("A missing code is generated and stored")
    func generatesAndStores() {
        let storage = InMemoryJoinCodeStorage()
        let model = GameJoinCodeModel(defaults: nil, codeStorage: storage)

        #expect(GameJoinCodeModel.isValidCode(model.masterCode))
        #expect(storage.values[Self.masterKey] == model.masterCode)
        #expect(storage.values[Self.playerKey] == model.playerCode)
    }

    @Test("A stored code is kept")
    func keepsStoredCode() {
        let storage = InMemoryJoinCodeStorage(values: [Self.masterKey: "1234", Self.playerKey: "5678"])
        let model = GameJoinCodeModel(defaults: nil, codeStorage: storage)

        #expect(model.masterCode == "1234")
        #expect(model.playerCode == "5678")
    }

    @Test("An unreadable keychain never replaces a stored code (§5.5)")
    func unavailableKeychainKeepsStoredCode() {
        let storage = InMemoryJoinCodeStorage(values: [Self.masterKey: "1234"], isUnavailable: true)
        let model = GameJoinCodeModel(defaults: nil, codeStorage: storage)
        #expect(storage.values[Self.masterKey] == "1234")

        storage.isUnavailable = false
        model.refreshFromStorage()

        #expect(model.masterCode == "1234")
        #expect(storage.values[Self.masterKey] == "1234")
    }

    @Test("A code generated while the keychain was unavailable is stored once it is readable (§5.5)")
    func provisionalCodeIsPersistedLater() {
        let storage = InMemoryJoinCodeStorage(isUnavailable: true)
        let model = GameJoinCodeModel(defaults: nil, codeStorage: storage)
        storage.isUnavailable = false

        model.refreshFromStorage()

        #expect(storage.values[Self.masterKey] == model.masterCode)
        #expect(storage.values[Self.playerKey] == model.playerCode)
    }

    @Test("A legacy UserDefaults code moves to storage after a verified write")
    func migratesLegacyDefaults() throws {
        let suite = "GameJoinCodeModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("4321", forKey: Self.masterKey)
        let storage = InMemoryJoinCodeStorage()

        let model = GameJoinCodeModel(defaults: defaults, codeStorage: storage)

        #expect(model.masterCode == "4321")
        #expect(storage.values[Self.masterKey] == "4321")
        #expect(defaults.string(forKey: Self.masterKey) == nil)
    }

    @Test("A legacy code stays in UserDefaults when the write fails")
    func keepsLegacyWhenWriteFails() throws {
        let suite = "GameJoinCodeModelTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("4321", forKey: Self.masterKey)
        // Reads say "not found" but writes fail: unavailable is the closest fake.
        let storage = InMemoryJoinCodeStorage(isUnavailable: true)

        let model = GameJoinCodeModel(defaults: defaults, codeStorage: storage)

        #expect(model.masterCode != "")
        #expect(defaults.string(forKey: Self.masterKey) == "4321")
    }

    @Test("The remembered code is only offered for the host that accepted it (§5.9)")
    func rememberedCodeIsPerHost() async {
        let storage = InMemoryJoinCodeStorage()
        let model = GameJoinCodeModel(defaults: nil, codeStorage: storage)

        model.rememberMasterJoinCode("2468", forHost: "Curse of Strahd")

        #expect(model.rememberedMasterJoinCode(forHost: "Curse of Strahd") == "2468")
        #expect(model.rememberedMasterJoinCode(forHost: "Other Game") == nil)
        await model.flushPendingWrites()
        #expect(storage.values[Self.lastCodeKey] == "2468")
        #expect(storage.values[Self.lastHostKey] == "Curse of Strahd")
    }

    @Test("An invalid code is not remembered")
    func invalidCodeIsNotRemembered() {
        let model = GameJoinCodeModel(defaults: nil, codeStorage: InMemoryJoinCodeStorage())

        model.rememberMasterJoinCode("٤٨٢١", forHost: "Host")

        #expect(model.rememberedMasterJoinCode(forHost: "Host") == nil)
    }

    @Test("Reset replaces both codes and forgets the remembered host code")
    func resetReplacesAndForgets() async {
        let storage = InMemoryJoinCodeStorage(values: [Self.masterKey: "1111", Self.playerKey: "2222"])
        let model = GameJoinCodeModel(defaults: nil, codeStorage: storage)
        model.rememberMasterJoinCode("3333", forHost: "Host")
        await model.flushPendingWrites()

        model.reset()
        await model.flushPendingWrites()

        #expect(GameJoinCodeModel.isValidCode(model.masterCode))
        #expect(model.rememberedMasterJoinCode(forHost: "Host") == nil)
        #expect(storage.values[Self.masterKey] == model.masterCode)
        #expect(storage.values[Self.lastCodeKey] == nil)
        #expect(storage.values[Self.lastHostKey] == nil)
    }

    @Test("A write that fails is retried on the next flush")
    func failedWriteIsRetried() async {
        let storage = InMemoryJoinCodeStorage(values: [Self.masterKey: "1111", Self.playerKey: "2222"])
        let model = GameJoinCodeModel(defaults: nil, codeStorage: storage)
        storage.isUnavailable = true
        model.masterCode = "9999"
        await model.flushPendingWrites()
        #expect(storage.values[Self.masterKey] == "1111")

        storage.isUnavailable = false
        await model.flushPendingWrites()

        #expect(storage.values[Self.masterKey] == "9999")
    }

    @Test("Flushing the pending writes does not write on the main thread (Game_Shareplay §3.4)")
    func flushDoesNotWriteOnTheMainThread() async {
        // Given - a Keychain that records where it is written. Which thread writes is what
        // decides whether the main actor can stall; a stopwatch on the main actor would depend
        // on how busy the test machine is.
        let storage = ThreadRecordingWriteStorage()
        let model = GameJoinCodeModel(defaults: nil, codeStorage: storage)
        // `init` stores the codes it generates on the calling thread; only the flush counts here.
        let writesAtInit = storage.writeCount
        let mainWritesAtInit = storage.mainThreadWriteCount
        model.masterCode = "1111"
        model.playerCode = "2222"

        // When
        await model.flushPendingWrites()

        // Then
        #expect(storage.writeCount - writesAtInit >= 2)
        #expect(storage.mainThreadWriteCount == mainWritesAtInit)
        #expect(storage.values[Self.masterKey] == "1111")
        #expect(storage.values[Self.playerKey] == "2222")
    }
}

/// A Keychain that records the threads it is written from.
private final class ThreadRecordingWriteStorage: JoinCodeStorage {
    private let base = InMemoryJoinCodeStorage()
    private let counts = Mutex<(total: Int, main: Int)>((0, 0))

    var writeCount: Int { counts.withLock { $0.total } }
    var mainThreadWriteCount: Int { counts.withLock { $0.main } }

    var values: [String: String] { base.values }

    func read(forKey key: String) -> JoinCodeReadResult { base.read(forKey: key) }

    func set(_ value: String, forKey key: String) -> Bool {
        pause()
        return base.set(value, forKey: key)
    }

    func remove(forKey key: String) -> Bool {
        pause()
        return base.remove(forKey: key)
    }

    private func pause() {
        let onMain = Thread.isMainThread
        counts.withLock {
            $0.total += 1
            if onMain { $0.main += 1 }
        }
    }
}
#endif
