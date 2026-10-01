// @copyright André Trettin

import Foundation
import Synchronization

@testable import GameRPG

/// Volatile `JoinCodeStorage` for tests, so they never touch the real Keychain.
/// `unavailable` simulates a locked keychain.
final class InMemoryJoinCodeStorage: JoinCodeStorage {
    private struct State {
        var values: [String: String] = [:]
        var isUnavailable = false
    }

    private let state: Mutex<State>

    init(values: [String: String] = [:], isUnavailable: Bool = false) {
        state = Mutex(State(values: values, isUnavailable: isUnavailable))
    }

    var isUnavailable: Bool {
        get { state.withLock { $0.isUnavailable } }
        set { state.withLock { $0.isUnavailable = newValue } }
    }

    var values: [String: String] {
        state.withLock { $0.values }
    }

    func read(forKey key: String) -> JoinCodeReadResult {
        state.withLock { state in
            if state.isUnavailable { return .unavailable }
            return state.values[key].map(JoinCodeReadResult.found) ?? .notFound
        }
    }

    @discardableResult
    func set(_ value: String, forKey key: String) -> Bool {
        state.withLock { state in
            guard !state.isUnavailable else { return false }
            state.values[key] = value
            return true
        }
    }

    @discardableResult
    func remove(forKey key: String) -> Bool {
        state.withLock { state in
            guard !state.isUnavailable else { return false }
            state.values.removeValue(forKey: key)
            return true
        }
    }
}
