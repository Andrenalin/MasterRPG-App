// @copyright André Trettin

import Foundation

/// JSONDecoder factory for CRDT operations.
///
/// JSONDecoder has mutable configuration, so callers get a fresh decoder instead
/// of sharing one mutable instance across tasks.
public actor DecoderPool: Sendable {
    public static let shared = DecoderPool()

    private init() {}

    /// Returns a new decoder. Kept as an actor method so old call sites can still
    /// await `DecoderPool.shared.getDecoder()` without sharing mutable state.
    public func getDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}
