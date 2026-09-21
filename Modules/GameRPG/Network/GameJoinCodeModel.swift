// @copyright André Trettin

import CoreRPG
import Observation
import os.log
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
    public convenience init() {
        self.init(defaults: .standard, codeStorage: KeychainJoinCodeStorage())
    }

    init(defaults: UserDefaults?, codeStorage: any JoinCodeStorage = KeychainJoinCodeStorage()) {
        self.defaults = defaults
        self.codeStorage = codeStorage
        var unresolved: Set<String> = []
        masterCode = Self.loadOrGenerate(key: Self.masterCodeKey, storage: codeStorage, legacyDefaults: defaults, unresolved: &unresolved)
        playerCode = Self.loadOrGenerate(key: Self.playerCodeKey, storage: codeStorage, legacyDefaults: defaults, unresolved: &unresolved)
        lastUsedMasterJoinCode = Self.loadOptional(key: Self.lastUsedMasterJoinCodeKey, storage: codeStorage, legacyDefaults: defaults, unresolved: &unresolved)
        lastUsedMasterHost = Self.loadHost(storage: codeStorage, unresolved: &unresolved)
        unresolvedKeys = unresolved
    }

    private let defaults: UserDefaults?
    /// Backs all codes below, including `lastUsedMasterJoinCode` — it
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

    /// Keys whose value could not be read or written when the model was created (keychain
    /// locked or unavailable). Their in-memory value is provisional: a generated code is not
    /// written, and a stored code is not yet known. `refreshFromStorage()` resolves them, so a
    /// locked-keychain launch can never replace a code that was already shared with players.
    /// See CODE_AUDIT_Join §5.5.
    @ObservationIgnored private var unresolvedKeys: Set<String>
    @ObservationIgnored private var isApplyingStoredValue = false

    private func persist(_ value: String?, forKey key: String) {
        guard !isApplyingStoredValue else { return }
        unresolvedKeys.remove(key)
        writeBuffer.enqueue(value, forKey: key)
        let buffer = writeBuffer
        let storage = codeStorage
        Task.detached(priority: .utility) {
            buffer.flush(to: storage)
        }
    }

    /// Writes any queued change now, on the calling thread. Called right before a code is put to
    /// use (hosting/joining), so a code changed moments ago is durable even if the app is
    /// suspended straight afterwards. See CODE_AUDIT_Join §3.3.
    public func flushPendingWrites() {
        writeBuffer.flush(to: codeStorage)
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
    /// Tried automatically on the next "Connect" tap for *that* host before
    /// falling back to prompting for a fresh code — see `BrowserRowView`.
    public private(set) var lastUsedMasterJoinCode: String? {
        didSet {
            guard oldValue != lastUsedMasterJoinCode else { return }
            persist(lastUsedMasterJoinCode, forKey: Self.lastUsedMasterJoinCodeKey)
        }
    }

    /// The host `lastUsedMasterJoinCode` was accepted by. A code is only offered again for the
    /// same host: replaying it against any other advertiser burned one of that host's failure
    /// allowances and handed it a handshake derived from an unrelated code.
    /// See CODE_AUDIT_Join §5.9.
    public private(set) var lastUsedMasterHost: String? {
        didSet {
            guard oldValue != lastUsedMasterHost else { return }
            persist(lastUsedMasterHost, forKey: Self.lastUsedMasterHostKey)
        }
    }

    /// The remembered Game Master code, only if it was accepted by `host`.
    public func rememberedMasterJoinCode(forHost host: String) -> String? {
        guard lastUsedMasterHost == host else { return nil }
        return lastUsedMasterJoinCode
    }

    public func rememberMasterJoinCode(_ code: String, forHost host: String) {
        guard Self.isValidCode(code) else { return }
        lastUsedMasterHost = host
        lastUsedMasterJoinCode = code
    }

    /// A fresh, random 4-digit code (`"0000"`...`"9999"`, always zero-padded).
    public static func randomCode() -> String {
        let digits = String(Int.random(in: 0...9999))
        return String(repeating: "0", count: Self.codeLength - digits.count) + digits
    }

    /// Regenerates `masterCode` and `playerCode` and clears the remembered host code,
    /// replacing every code this device has stored in the Keychain. Each property's
    /// own `didSet` handles the actual Keychain write/removal — see their doc
    /// comments — so this only needs to assign new values. Exposed from
    /// Settings so a user can invalidate codes they suspect were shared too
    /// widely, without waiting for the per-code shuffle on the setup screens.
    public func reset() {
        masterCode = Self.randomCode()
        playerCode = Self.randomCode()
        lastUsedMasterJoinCode = nil
        lastUsedMasterHost = nil
    }

    /// Retries every value that could not be resolved at creation. Cheap no-op once everything
    /// is resolved. Call before a code is used (hosting, joining) and when the app becomes active.
    public func refreshFromStorage() {
        guard !unresolvedKeys.isEmpty else { return }
        for key in unresolvedKeys {
            let result = codeStorage.read(forKey: key)
            switch (key, result) {
            case (_, .unavailable):
                continue
            case (Self.masterCodeKey, .found(let stored)) where Self.isValidCode(stored):
                apply { masterCode = stored }
            case (Self.playerCodeKey, .found(let stored)) where Self.isValidCode(stored):
                apply { playerCode = stored }
            case (Self.lastUsedMasterJoinCodeKey, .found(let stored)) where Self.isValidCode(stored):
                apply { lastUsedMasterJoinCode = stored }
            case (Self.lastUsedMasterHostKey, .found(let stored)):
                apply { lastUsedMasterHost = stored }
            case (Self.masterCodeKey, _):
                guard codeStorage.set(masterCode, forKey: key) else { continue }
            case (Self.playerCodeKey, _):
                guard codeStorage.set(playerCode, forKey: key) else { continue }
            default:
                break
            }
            unresolvedKeys.remove(key)
        }
    }

    private func apply(_ change: () -> Void) {
        isApplyingStoredValue = true
        change()
        isApplyingStoredValue = false
    }

    private static func loadOrGenerate(
        key: String,
        storage: any JoinCodeStorage,
        legacyDefaults: UserDefaults?,
        unresolved: inout Set<String>
    ) -> String {
        switch storage.read(forKey: key) {
        case .found(let stored) where isValidCode(stored):
            return stored
        case .unavailable:
            // Do not replace a code that may exist but cannot be read right now.
            unresolved.insert(key)
            return randomCode()
        default:
            break
        }
        // Migrate a pre-existing `UserDefaults`-stored code (this model's storage before
        // CODE_AUDIT §6.2) into the Keychain instead of silently generating a new one, which
        // would invalidate any code the user already shared out-of-band.
        if let legacy = legacyDefaults?.string(forKey: key), isValidCode(legacy) {
            if storage.set(legacy, forKey: key) {
                legacyDefaults?.removeObject(forKey: key)
            } else {
                unresolved.insert(key)
            }
            return legacy
        }
        let generated = randomCode()
        if !storage.set(generated, forKey: key) {
            unresolved.insert(key)
        }
        return generated
    }

    /// Mirrors `loadOrGenerate` for a code that has no "generate a fresh one if missing"
    /// fallback — it's fine for this to simply be unset. See CODE_AUDIT §6.2.
    private static func loadOptional(
        key: String,
        storage: any JoinCodeStorage,
        legacyDefaults: UserDefaults?,
        unresolved: inout Set<String>
    ) -> String? {
        switch storage.read(forKey: key) {
        case .found(let stored) where isValidCode(stored):
            return stored
        case .unavailable:
            unresolved.insert(key)
            return nil
        default:
            break
        }
        if let legacy = legacyDefaults?.string(forKey: key), isValidCode(legacy) {
            if storage.set(legacy, forKey: key) {
                legacyDefaults?.removeObject(forKey: key)
            }
            return legacy
        }
        return nil
    }

    private static func loadHost(storage: any JoinCodeStorage, unresolved: inout Set<String>) -> String? {
        switch storage.read(forKey: lastUsedMasterHostKey) {
        case .found(let host):
            return host
        case .unavailable:
            unresolved.insert(lastUsedMasterHostKey)
            return nil
        case .notFound:
            return nil
        }
    }

    /// A code is exactly four ASCII digits. Other Unicode digits (Arabic-Indic, full-width,
    /// superscripts) are "numbers" to `Character` but encode to different bytes, so they would
    /// derive a different key than the host's ASCII code and fail as a wrong code.
    /// See CODE_AUDIT_Join §5.7.
    static func isValidCode(_ code: String) -> Bool {
        code.count == Self.codeLength && code.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Normalises typed or pasted input to at most `codeLength` ASCII digits, converting other
    /// Unicode decimal digits (e.g. from an Arabic or Persian keypad) to their ASCII value.
    static func sanitized(_ input: String) -> String {
        let digits = input.compactMap { character -> Character? in
            guard let value = character.wholeNumberValue, (0...9).contains(value) else { return nil }
            return Character(String(value))
        }
        return String(digits.prefix(codeLength))
    }

    /// Digit count for every join code. See CODE_AUDIT §9.12 — previously
    /// duplicated as a bare `4` in both `randomCode()` and `isValidCode(_:)`.
    static let codeLength = 4
    private static let masterCodeKey = "MasterRPGMasterJoinCode"
    private static let playerCodeKey = "MasterRPGPlayerJoinCode"
    private static let lastUsedMasterJoinCodeKey = "MasterRPGLastUsedMasterJoinCode"
    private static let lastUsedMasterHostKey = "MasterRPGLastUsedMasterHost"
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
                let succeeded = if let value {
                    storage.set(value, forKey: key)
                } else {
                    storage.remove(forKey: key)
                }
                if !succeeded {
                    // The key is public; the value is never logged. Keep the change queued for the
                    // next flush unless a newer value already superseded it.
                    Logger.networking.error("GameJoinCodeModel: Keychain write failed for \(key, privacy: .public)")
                    pending.withLock { pending in
                        if pending.index(forKey: key) == nil {
                            pending[key] = .some(value)
                        }
                    }
                }
            }
        }
    }
}
