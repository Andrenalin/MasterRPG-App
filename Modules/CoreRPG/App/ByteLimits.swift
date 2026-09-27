// @copyright André Trettin

import Foundation

/// Binary byte units, so size limits are written in one unit instead of a mix of decimal and
/// binary literals. See CODE_AUDIT_18 §9.17.
public enum ByteUnit {
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
