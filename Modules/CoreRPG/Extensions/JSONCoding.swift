// @copyright André Trettin

import Foundation

/// Shared `JSONEncoder`/`JSONDecoder` instances for call sites that would otherwise allocate a
/// fresh instance per encode/decode call — the same pattern `NavigationSceneStorage` already
/// uses internally. `JSONEncoder`/`JSONDecoder` allocation is cheap relative to the encode/decode
/// work itself, so this is a style/consistency win rather than a measured perf fix; adopt it
/// opportunistically in hot, repeatedly-called paths (e.g. wire-protocol encode/decode) rather
/// than as a blanket sweep. See CODE_AUDIT §7.4.
public enum JSONCoding {
    public static let encoder = JSONEncoder()
    public static let decoder = JSONDecoder()
}
