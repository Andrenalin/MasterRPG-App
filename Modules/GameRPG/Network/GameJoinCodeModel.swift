// @copyright André Trettin

import Observation
import SwiftUI

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
        lastUsedMasterJoinCode = UserDefaults.standard.string(forKey: Self.lastUsedMasterJoinCodeKey)
    }

    init(defaults: UserDefaults, codeStorage: any JoinCodeStorage = KeychainJoinCodeStorage()) {
        self.defaults = defaults
        self.codeStorage = codeStorage
        masterCode = Self.loadOrGenerate(key: Self.masterCodeKey, storage: codeStorage, legacyDefaults: defaults)
        playerCode = Self.loadOrGenerate(key: Self.playerCodeKey, storage: codeStorage, legacyDefaults: defaults)
        lastUsedMasterJoinCode = defaults.string(forKey: Self.lastUsedMasterJoinCodeKey)
    }

    private let defaults: UserDefaults?
    /// Backs `masterCode`/`playerCode` — the codes that gate network trust between devices.
    /// `lastUsedMasterJoinCode` below stays in `defaults`: it's a remembered convenience value
    /// (a code entered for joining a *different* device), not a secret this device presents.
    /// See CODE_AUDIT §6.2.
    private let codeStorage: any JoinCodeStorage

    public var masterCode: String {
        didSet {
            guard oldValue != masterCode else { return }
            codeStorage.set(masterCode, forKey: Self.masterCodeKey)
        }
    }

    public var playerCode: String {
        didSet {
            guard oldValue != playerCode else { return }
            codeStorage.set(playerCode, forKey: Self.playerCodeKey)
        }
    }

    /// The code this device last used to successfully join a Game Master.
    /// Tried automatically on the next "Connect" tap for that role before
    /// falling back to prompting for a fresh code — see `BrowserRowView`.
    public var lastUsedMasterJoinCode: String? {
        didSet {
            guard oldValue != lastUsedMasterJoinCode else { return }
            if let lastUsedMasterJoinCode {
                defaults?.set(lastUsedMasterJoinCode, forKey: Self.lastUsedMasterJoinCodeKey)
            } else {
                defaults?.removeObject(forKey: Self.lastUsedMasterJoinCodeKey)
            }
        }
    }

    /// A fresh, random 4-digit code (`"0000"`...`"9999"`, always zero-padded).
    public static func randomCode() -> String {
        let digits = String(Int.random(in: 0...9999))
        return String(repeating: "0", count: 4 - digits.count) + digits
    }

    private static func loadOrGenerate(key: String, storage: any JoinCodeStorage, legacyDefaults: UserDefaults?) -> String {
        if let stored = storage.string(forKey: key), isValidCode(stored) {
            return stored
        }
        // Migrate a pre-existing `UserDefaults`-stored code (this model's storage before
        // CODE_AUDIT §6.2) into the Keychain instead of silently generating a new one, which
        // would invalidate any code the user already shared out-of-band.
        if let legacy = legacyDefaults?.string(forKey: key), isValidCode(legacy) {
            storage.set(legacy, forKey: key)
            legacyDefaults?.removeObject(forKey: key)
            return legacy
        }
        let generated = randomCode()
        storage.set(generated, forKey: key)
        return generated
    }

    static func isValidCode(_ code: String) -> Bool {
        code.count == 4 && code.allSatisfy(\.isNumber)
    }

    private static let masterCodeKey = "MasterRPGMasterJoinCode"
    private static let playerCodeKey = "MasterRPGPlayerJoinCode"
    private static let lastUsedMasterJoinCodeKey = "MasterRPGLastUsedMasterJoinCode"
}
