// @copyright André Trettin

import Observation
import SwiftUI

/// Per-device join codes that gate local-network pairing.
///
/// Unlike the old hardcoded `GameSecurity.passcode` — a single secret shared
/// by every install of the app, letting any nearby device join or inject
/// state into someone else's game — these codes are generated randomly per
/// installation, persisted in `UserDefaults`, and can be changed by the user
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
        masterCode = Self.loadOrGenerate(key: Self.masterCodeKey, defaults: .standard)
        playerCode = Self.loadOrGenerate(key: Self.playerCodeKey, defaults: .standard)
        lastUsedMasterJoinCode = UserDefaults.standard.string(forKey: Self.lastUsedMasterJoinCodeKey)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        masterCode = Self.loadOrGenerate(key: Self.masterCodeKey, defaults: defaults)
        playerCode = Self.loadOrGenerate(key: Self.playerCodeKey, defaults: defaults)
        lastUsedMasterJoinCode = defaults.string(forKey: Self.lastUsedMasterJoinCodeKey)
    }

    private let defaults: UserDefaults?

    public var masterCode: String {
        didSet {
            guard oldValue != masterCode else { return }
            defaults?.set(masterCode, forKey: Self.masterCodeKey)
        }
    }

    public var playerCode: String {
        didSet {
            guard oldValue != playerCode else { return }
            defaults?.set(playerCode, forKey: Self.playerCodeKey)
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

    private static func loadOrGenerate(key: String, defaults: UserDefaults) -> String {
        if let stored = defaults.string(forKey: key), isValidCode(stored) {
            return stored
        }
        let generated = randomCode()
        defaults.set(generated, forKey: key)
        return generated
    }

    static func isValidCode(_ code: String) -> Bool {
        code.count == 4 && code.allSatisfy(\.isNumber)
    }

    private static let masterCodeKey = "MasterRPGMasterJoinCode"
    private static let playerCodeKey = "MasterRPGPlayerJoinCode"
    private static let lastUsedMasterJoinCodeKey = "MasterRPGLastUsedMasterJoinCode"
}
