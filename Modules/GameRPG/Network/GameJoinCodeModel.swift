// @copyright André Trettin

import Observation
import SwiftUI
import Synchronization

/// Per-device join codes that gate local-network pairing.
///
/// Unlike the old hardcoded `GameSecurity.passcode` — a single secret shared
/// by every install of the app, letting any nearby device join or inject
/// state into someone else's game — these codes are generated randomly per
/// installation, persisted in the Keychain, and can be changed by the user
/// at any time from the game setup screen.
///
/// Two independent codes exist because two independent listeners exist:
/// - `masterCode` gates this device's primary game listener, i.e. the one a
///   Player/Observer browses and connects to when this device hosts as
///   Game Master (`GameServiceType.player`).
/// - `playerCode` gates this device's proxy listener, i.e. the one another
///   Player browses and connects to when this device relays for further
///   players (`GameServiceType.proxyServer`).
///
/// A joining device must be told the relevant code out-of-band (read aloud,
/// messaged, etc.) and enter it in the Join UI before a connection attempt
/// is made; a mismatched code fails the TLS handshake like any other
/// connection failure.
@MainActor @Observable
public final class GameJoinCodeModel: Sendable {
    public init() {
        self.defaults = .standard
        self.codeStorage = KeychainJoinCodeStorage()
        masterCode = Self.loadOrGenerate(key: Self.masterCodeKey, storage: codeStorage, legacyDefaults: defaults)
        playerCode = Self.loadOrGenerate(key: Self.playerCodeKey, storage: codeStorage, legacyDefaults: defaults)
        lastUsedMasterJoinCode = Self.loadLastUsedMasterJoinCode(storage: codeStorage, legacyDefaults: defaults)
    }

    init(defaults: UserDefaults, codeStorage: any JoinCodeStorage = KeychainJoinCodeStorage()) {
        self.defaults = defaults
        self.codeStorage = codeStorage
        masterCode = Self.loadOrGenerate(key: Self.masterCodeKey, storage: codeStorage, legacyDefaults: defaults)
        playerCode = Self.loadOrGenerate(key: Self.playerCodeKey, storage: codeStorage, legacyDefaults: defaults)
        lastUsedMasterJoinCode = Self.loadLastUsedMasterJoinCode(storage: codeStorage, legacyDefaults: defaults)
    }

    private let defaults: UserDefaults?
    /// Backs all three codes below, including `lastUsedMasterJoinCode` — it
    /// is still a live authentication secret (the code currently granting
    /// access to whatever game it was last used to join), so it belongs in
    /// the same Keychain-backed, non-backed-up storage as `masterCode`/
    /// `playerCode` rather than UserDefaults. See CODE_AUDIT §6.2.
    private let codeStorage: any JoinCodeStorage

    /// Keychain writes are synchronous, so they happen off the main actor. Values are queued in
    /// order on the main actor (`enqueue`) and written by `flush`, which holds one lock while it
    /// takes and writes the pending entries — a superseded value can therefore never be written
    /// after the newer one, which per-write detached tasks could not guarantee.
    /// See CODE_AUDIT_15 §3.13.
    private let writeBuffer = JoinCodeWriteBuffer()

    private func persist(_ value: String?, forKey key: String) {
        writeBuffer.enqueue(value, forKey: key)
        let buffer = writeBuffer
        let storage = codeStorage
        Task.detached(priority: .utility) {
            buffer.flush(to: storage)
        }
    }

    public var masterCode: String {
        didSet {
            guard oldValue != masterCode else { return }
            persist(masterCode, forKey: Self.masterCodeKey)
        }
    }

    public var playerCode: String {
        didSet {
            guard oldValue != playerCode else { return }
            persist(playerCode, forKey: Self.playerCodeKey)
        }
    }

    /// The code this device last used to successfully join a Game Master.
    /// Tried automatically on the next "Connect" tap for that role before
    /// falling back to prompting for a fresh code — see `BrowserRowView`.
    public var lastUsedMasterJoinCode: String? {
        didSet {
            guard oldValue != lastUsedMasterJoinCode else { return }
            persist(lastUsedMasterJoinCode, forKey: Self.lastUsedMasterJoinCodeKey)
        }
    }

    /// A fresh, random 4-digit code (`"0000"`...`"9999"`, always zero-padded).
    public static func randomCode() -> String {
        let digits = String(Int.random(in: 0...9999))
        return String(repeating: "0", count: Self.codeLength - digits.count) + digits
    }

    /// Regenerates `masterCode` and `playerCode` and clears `lastUsedMasterJoinCode`,
    /// replacing every code this device has stored in the Keychain. Each property's
    /// own `didSet` handles the actual Keychain write/removal — see their doc
    /// comments — so this only needs to assign new values. Exposed from
    /// Settings so a user can invalidate codes they suspect were shared too
    /// widely, without waiting for the per-code shuffle on the setup screens.
    public func reset() {
        masterCode = Self.randomCode()
        playerCode = Self.randomCode()
        lastUsedMasterJoinCode = nil
    }

    private static func loadOrGenerate(key: String, storage: any JoinCodeStorage, legacyDefaults: UserDefaults?) -> String {
        if let stored = storage.string(forKey: key), isValidCode(stored) {
            return stored
        }
        // Migrate a pre-existing `UserDefaults`-stored code (this model's storage before
        // CODE_AUDIT §6.2) into the Keychain instead of silently generating a new one, which
        // would invalidate any code the user already shared out-of-band.
        if let legacy = legacyDefaults?.string(forKey: key), isValidCode(legacy) {
            if storage.set(legacy, forKey: key) {
                legacyDefaults?.removeObject(forKey: key)
            }
            return legacy
        }
        let generated = randomCode()
        storage.set(generated, forKey: key)
        return generated
    }

    /// Mirrors `loadOrGenerate` for the one code that has no "generate a
    /// fresh one if missing" fallback — it's fine for this to simply be
    /// unset. See CODE_AUDIT §6.2.
    private static func loadLastUsedMasterJoinCode(
        storage: any JoinCodeStorage,
        legacyDefaults: UserDefaults?
    ) -> String? {
        if let stored = storage.string(forKey: lastUsedMasterJoinCodeKey), isValidCode(stored) {
            return stored
        }
        if let legacy = legacyDefaults?.string(forKey: lastUsedMasterJoinCodeKey), isValidCode(legacy) {
            if storage.set(legacy, forKey: lastUsedMasterJoinCodeKey) {
                legacyDefaults?.removeObject(forKey: lastUsedMasterJoinCodeKey)
            }
            return legacy
        }
        return nil
    }

    static func isValidCode(_ code: String) -> Bool {
        code.count == Self.codeLength && code.allSatisfy(\.isNumber)
    }

    /// Digit count for every join code. See CODE_AUDIT §9.12 — previously
    /// duplicated as a bare `4` in both `randomCode()` and `isValidCode(_:)`.
    private static let codeLength = 4
    private static let masterCodeKey = "MasterRPGMasterJoinCode"
    private static let playerCodeKey = "MasterRPGPlayerJoinCode"
    private static let lastUsedMasterJoinCodeKey = "MasterRPGLastUsedMasterJoinCode"
}

/// Ordered hand-off of join-code changes to the Keychain; see `GameJoinCodeModel.persist`.
private final class JoinCodeWriteBuffer: Sendable {
    /// `nil` value = remove the stored code.
    private let pending = Mutex<[String: String?]>([:])
    private let writeLock = Mutex<Void>(())

    func enqueue(_ value: String?, forKey key: String) {
        pending.withLock { $0[key] = .some(value) }
    }

    func flush(to storage: any JoinCodeStorage) {
        writeLock.withLock { _ in
            let entries = pending.withLock { pending in
                let taken = pending
                pending.removeAll()
                return taken
            }
            for (key, value) in entries {
                if let value {
                    storage.set(value, forKey: key)
                } else {
                    storage.remove(forKey: key)
                }
            }
        }
    }
}
