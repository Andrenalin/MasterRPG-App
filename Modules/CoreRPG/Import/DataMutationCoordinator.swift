// @copyright André Trettin

import Foundation
import Observation

/// Process-wide exclusion for operations that mutate the shared RPG controller graph.
///
/// The coordinator lives in CoreRPG so imports launched by lower-level modules participate in
/// the same exclusion as application-level imports and database repair operations.
@MainActor @Observable
public final class DataMutationCoordinator: Sendable {
    @MainActor public static let shared = DataMutationCoordinator()

    public private(set) var isActive = false

    @ObservationIgnored private var activeToken: UUID?

    public init() {}

    /// Returns an ownership token, or `nil` when another mutation is already active.
    public func begin() -> UUID? {
        guard activeToken == nil else { return nil }

        let token = UUID()
        activeToken = token
        isActive = true
        return token
    }

    /// Releases the coordinator only when `token` belongs to the active operation.
    public func end(_ token: UUID) {
        guard activeToken == token else { return }

        activeToken = nil
        isActive = false
    }
}
