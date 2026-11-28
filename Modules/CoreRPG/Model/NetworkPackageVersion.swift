// @copyright André Trettin

import Foundation

/// A file-backed item (Photo, Pdf, Space) whose metadata players see: its name, description,
/// rotation and entries. `version` covers only the file, so a rename, a new rotation or new
/// bookmarks left the package fingerprint and the player's `hasItem(id:version:)` unchanged and
/// never reached a player who already held the file. See CODE_AUDIT_Edit_Save §5.10.
@MainActor
public protocol NetworkMetadataDigestible {
    /// Deterministic across devices (never `hashValue`).
    var networkMetadataDigest: Int { get }
}

/// The version that identifies an item's game package: the item's `version`, combined with the
/// metadata digest for a file-backed item. The asset version (`networkVersion(for:)`, the file
/// alone) stays what transfers, receipts and ledgers compare, so a metadata edit re-sends the
/// small package but never the file bytes.
public enum NetworkPackageVersion {
    @MainActor
    public static func of(_ item: some ItemDiffComparable) -> Int {
        of(item, version: item.version)
    }

    /// The package version for the asset version `version` (the module's network version).
    @MainActor
    public static func of(_ item: some ItemDiffComparable, version: Int) -> Int {
        guard let digestible = item as? any NetworkMetadataDigestible else { return version }
        return StableVersionDigest.digest([version, digestible.networkMetadataDigest])
    }

    /// Whether the package version differs from the asset version for this kind of item.
    @MainActor
    public static func hasMetadataDigest(_ item: some ItemDiffComparable) -> Bool {
        item is any NetworkMetadataDigestible
    }

    /// The digest of what a player sees of a file-backed item. Tags and category are left out:
    /// imports normalise them, so they would differ between master and player.
    @MainActor
    public static func metadataDigest<Entry: EntryDataAccessible>(name: String, description: String, entries: [Entry], degrees: Double? = nil) -> Int {
        StableVersionDigest.digest(CanonicalFileMetadata(
            name: name,
            description: description,
            entries: entries.map { [$0.id.uuidString, $0.name, $0.content] },
            degrees: degrees
        ))
    }
}

private struct CanonicalFileMetadata: Encodable {
    let name: String
    let description: String
    let entries: [[String]]
    let degrees: Double?
}
