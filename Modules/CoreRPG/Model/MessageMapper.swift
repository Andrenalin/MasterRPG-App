// @copyright André Trettin

import Foundation

/// Shared contract for a network-message payload that round-trips through
/// `Data` for the game transport layer. Declared in CoreRPG (not GameRPG,
/// where it originated) since every module's own domain types need to
/// conform to it, and only CoreRPG sits below all of them.
public protocol MessageMapper: Sendable {
    func encodeData() -> Data?
    static func decodeData(of data: Data?) -> Self?
}

/// The mechanical case — a plain `JSONEncoder`/`JSONDecoder` round trip with
/// no extra options — covers most conformers. A type with a genuine reason to
/// diverge (e.g. deterministic key ordering, or its own error logging) can
/// still provide its own `encodeData()`/`decodeData(of:)` instead of this
/// default; conforming to `MessageMapper` doesn't force using it.
///
/// Uses the shared `JSONCoding` instances: this is the per-message network path they were
/// written for. See CODE_AUDIT_18 §9.14.
public extension MessageMapper where Self: Codable {
    func encodeData() -> Data? {
        try? JSONCoding.encoder.encode(self)
    }

    static func decodeData(of data: Data?) -> Self? {
        guard let data else { return nil }
        return try? JSONCoding.decoder.decode(Self.self, from: data)
    }
}
