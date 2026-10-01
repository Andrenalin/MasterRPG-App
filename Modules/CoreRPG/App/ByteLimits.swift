// @copyright André Trettin

import Foundation

/// Byte units, so size limits are written with a unit instead of a long literal.
/// See CODE_AUDIT_18 §9.17. Limits are binary (`mebibyte`) unless they must match a decimal
/// figure of an external system: the network limits use `megabyte`, the unit SharePlay's
/// documented message limits are quoted in. See CODE_AUDIT_20 §9.14.
public enum ByteUnit {
    /// Decimal (SI) megabyte: 1,000,000 bytes.
    public static let megabyte = 1_000_000
    public static let kibibyte = 1_024
    public static let mebibyte = 1_024 * kibibyte
    public static let gibibyte = 1_024 * mebibyte
}

/// Size limits shared by more than one target.
public enum ByteLimits {
    /// Largest single file the app or the share extension downloads, opens or caches on behalf
    /// of an item (256 MiB).
    public static let maximumSourceFileBytes = 256 * ByteUnit.mebibyte
}
