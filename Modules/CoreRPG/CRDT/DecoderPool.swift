// @copyright André Trettin

import Foundation

/// Thread-safe JSONDecoder pool to avoid creating new decoder instances on every CRDT operation
public actor DecoderPool: Sendable {
    public static let shared = DecoderPool()

    // JSONDecoder is thread-safe for decoding operations
    nonisolated(unsafe) private var decoder: JSONDecoder?

    private init() {}

    /// Get a decoder from the pool (creates one if none available)
    /// JSONDecoder is thread-safe for concurrent reads, so this is safe
    public func getDecoder() -> JSONDecoder {
        if let decoder = decoder {
            return decoder
        }
        let newDecoder = JSONDecoder()
        decoder = newDecoder
        return newDecoder
    }
}
