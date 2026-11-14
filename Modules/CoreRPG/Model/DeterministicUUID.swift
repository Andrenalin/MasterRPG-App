// @copyright André Trettin

import CryptoKit
import Foundation

/// UUIDs derived from a text key, identical on every device and in every run.
///
/// The ids are stored and synced (CloudKit merges rows with the same id), so the algorithm must
/// never change: SHA-256 of the key's UTF-8 bytes, the first 16 bytes, then the version and
/// variant bits. Never `hashValue`, which differs per run and per device. One place for it, after
/// the same steps had been written out three times. See CODE_AUDIT §9.6.
public enum DeterministicUUID {
    /// The version nibble written into the id. Ids made with one version are never re-made with
    /// the other, so a caller keeps the version it always used.
    public enum Version: UInt8, Sendable {
        /// Shaped like a name-based UUID v5 (`0x50`).
        case v5 = 0x50
        /// A version 8 (custom) UUID (`0x80`).
        case v8 = 0x80
    }

    public static func uuid(hashing key: String, version: Version) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | version.rawValue
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return uuid(bytes: bytes)
    }

    /// The UUID made of exactly these 16 bytes, unchanged.
    public static func uuid(bytes: [UInt8]) -> UUID {
        precondition(bytes.count == 16, "A UUID has 16 bytes")
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
