// @copyright André Trettin

import Foundation

/// Shared `JSONEncoder`/`JSONDecoder` instances for call sites that would otherwise allocate a
/// fresh instance per encode/decode call. `JSONEncoder`/`JSONDecoder` allocation is cheap relative to the encode/decode
/// work itself, so this is a style/consistency win rather than a measured perf fix; adopt it
/// opportunistically in hot, repeatedly-called paths (e.g. wire-protocol encode/decode) rather
/// than as a blanket sweep. See CODE_AUDIT §7.4.
public enum JSONCoding {
    public static let encoder = JSONEncoder()
    public static let decoder = JSONDecoder()

    /// Sorted keys: the same value always encodes to the same bytes (digests, persisted values
    /// compared byte for byte). See CODE_AUDIT_19 §9.17.
    public static let sortedKeysEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// ISO-8601 dates and sorted keys, for the import archive and source index files.
    /// See CODE_AUDIT_19 §9.17.
    public static let iso8601SortedKeysEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// Reads what `iso8601SortedKeysEncoder` writes.
    public static let iso8601Decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
