// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import Synchronization

/// The session id a hosting master advertises, kept across hosting runs with the same join code.
///
/// A master only redials reconnect services that carry its own session id, so it never dials
/// another group's players (CODE_AUDIT_Join §5.2). A fresh id per hosting run also excluded the
/// master's own players: after the master ended and restarted the game, the players still
/// advertised the previous id and were never redialed. The id now changes only with the join
/// code, when those players could not authenticate anyway (a new code, "Reset Join Codes").
///
/// Kept in memory for the app run, so ending and restarting a game always reuses it, and stored
/// with the join codes (Keychain-backed `JoinCodeStorage`, the entry contains the code) for the
/// next launch. If neither has it, hosting starts a fresh id.
final class HostingSessionStore: Sendable {
    /// The store of this app run; the default for every master controller.
    static let shared = HostingSessionStore()

    private let storage: any JoinCodeStorage
    /// Entries of this app run, by key.
    private let memory: Mutex<[String: String]>
    /// Whether `prewarm()` has read the stored entries, so a miss in memory means "none stored"
    /// without a Keychain read on the main actor. See CODE_AUDIT_20 §3.7.
    private let isPrewarmed = Mutex(false)
    /// Keychain writes, in order, so a later entry never lands before an earlier one.
    private let writeChain = Mutex<Task<Void, Never>?>(nil)

    init(storage: any JoinCodeStorage = KeychainJoinCodeStorage()) {
        self.storage = storage
        self.memory = Mutex([:])
    }

    /// Reads the stored entries into memory off the main actor, ahead of the first
    /// `sessionId(forPasscode:proxy:)`, which then never touches the Keychain on the caller.
    @concurrent
    func prewarm() async {
        for key in [Self.masterKey, Self.proxyKey] {
            if case .found(let stored) = storage.read(forKey: key) {
                memory.withLock { entries in
                    if entries[key] == nil { entries[key] = stored }
                }
            }
        }
        isPrewarmed.withLock { $0 = true }
    }

    func sessionId(forPasscode passcode: String, proxy: Bool) -> String {
        let key = proxy ? Self.proxyKey : Self.masterKey
        if let remembered = memory.withLock({ $0[key] }), let session = Self.session(from: remembered, passcode: passcode) {
            Logger.networking.debug("HostingSessionStore: Reusing the session of this app run")
            return session
        }
        if isPrewarmed.withLock({ $0 }) {
            // The stored entry is already in memory (and belongs to another code, or there is none).
            Logger.networking.debug("HostingSessionStore: No stored session for this code")
        } else {
            switch storage.read(forKey: key) {
            case .found(let stored):
                if let session = Self.session(from: stored, passcode: passcode) {
                    memory.withLock { $0[key] = stored }
                    Logger.networking.debug("HostingSessionStore: Reusing the stored session")
                    return session
                }
                Logger.networking.debug("HostingSessionStore: Stored session belongs to another code")
            case .notFound:
                Logger.networking.debug("HostingSessionStore: No stored session")
            case .unavailable:
                Logger.networking.error("HostingSessionStore: Stored session unavailable")
            }
        }
        let session = UUID().uuidString
        let entry = "\(passcode)\(Self.separator)\(session)"
        memory.withLock { $0[key] = entry }
        // The Keychain write runs off the caller; the in-memory entry already serves this run.
        let storage = storage
        writeChain.withLock { chain in
            let previous = chain
            chain = Task { @concurrent in
                await previous?.value
                let stored = storage.set(entry, forKey: key)
                Logger.networking.debug("HostingSessionStore: New session (stored: \(stored, privacy: .public))")
            }
        }
        return session
    }

    /// Suspends until every Keychain write started so far has finished.
    func waitForStoredWrites() async {
        let chain = writeChain.withLock { $0 }
        await chain?.value
    }

    private static func session(from stored: String, passcode: String) -> String? {
        let parts = stored.split(separator: separator, maxSplits: 1)
        guard parts.count == 2, parts[0] == passcode, !parts[1].isEmpty else { return nil }
        return String(parts[1])
    }

    private static let separator: Character = " "
    static let masterKey = "hostingSession"
    static let proxyKey = "proxyHostingSession"
}
