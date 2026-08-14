// @copyright André Trettin

import CryptoKit
import Foundation

/// Deterministic, cross-device version fingerprint: `JSONEncoder(.sortedKeys)`
/// → SHA256 → fold the first 8 bytes → non-zero `Int`. Deliberately not
/// `hashValue`, which Swift explicitly documents as randomized per process —
/// it would never agree between two devices, defeating the entire purpose of
/// a version number two peers compare over the network.
///
/// Extracted from three previously independent, byte-for-byte identical (or
/// near-identical) implementations — `CharacterRPG.ValueModel.StableValueVersion`,
/// `TableRPG.TableModel.StableTableVersion`, and
/// `CharacterRPG.CharacterPackageVersion` (which additionally sorts its input
/// before encoding). See CODE_AUDIT §9.11.
public enum StableVersionDigest {
    public static func digest<Value: Encodable>(_ value: Value) -> Int {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return 1 }
        let digest = SHA256.hash(data: data)
        let rawValue = digest.prefix(8).reduce(UInt64(0)) { partialResult, byte in
            partialResult << 8 | UInt64(byte)
        }
        let version = Int(bitPattern: UInt(truncatingIfNeeded: rawValue))
        return version == 0 ? 1 : version
    }
}
