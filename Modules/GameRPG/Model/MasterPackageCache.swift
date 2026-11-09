// @copyright André Trettin

import CoreRPG
import Foundation

/// The versions that identify what a package contains. The package of an item is valid for
/// another request as long as these are the ones the item has now: an edit changes them.
struct MasterPackageFingerprint: Equatable, Sendable {
    let version: Int
    let assetVersion: Int?
    let contentVersion: Int?

    init(version: Int, assetVersion: Int? = nil, contentVersion: Int? = nil) {
        self.version = version
        self.assetVersion = assetVersion
        self.contentVersion = contentVersion
    }

    init(_ data: NetworkCodableDataType) {
        self.init(version: data.version, assetVersion: data.assetVersion, contentVersion: data.contentVersion)
    }
}

/// The most recent packages the game master exported, so that N players asking for the same
/// item cost one export instead of N in a row inside the serial master pipeline.
///
/// A package is reused only while the item still has the fingerprint the package was made with
/// (an edit changes it), and only a few are kept, within the size of one frame, so the cache
/// never holds more than one large presentation. See CODE_AUDIT_Game_Shareplay §7.2.
struct MasterPackageCache {
    static let maximumEntries = 2
    static let maximumByteCount = GameLimits.maximumMessageBytes

    private struct Entry {
        let module: NetworkModules
        let itemId: UUID
        let fingerprint: MasterPackageFingerprint
        let package: NetworkCodableDataType
        var byteCount: Int { package.data?.count ?? 0 }
    }

    /// Newest first.
    private var entries: [Entry] = []
    private(set) var hitCount = 0

    var count: Int { entries.count }

    /// The package of `itemId` if it was exported for exactly `fingerprint`.
    mutating func package(
        for module: NetworkModules,
        itemId: UUID,
        matching fingerprint: MasterPackageFingerprint
    ) -> NetworkCodableDataType? {
        guard let index = entries.firstIndex(where: { $0.module == module && $0.itemId == itemId }) else {
            return nil
        }
        guard entries[index].fingerprint == fingerprint else {
            // Out of date: it can never match again.
            entries.remove(at: index)
            return nil
        }
        let entry = entries.remove(at: index)
        entries.insert(entry, at: 0)
        hitCount += 1
        return entry.package
    }

    /// Keeps the package as the newest one. A package without bytes, or one larger than the
    /// cache may hold, is not kept.
    mutating func store(_ package: NetworkCodableDataType) {
        entries.removeAll { $0.module == package.type && $0.itemId == package.id }
        guard let data = package.data, !data.isEmpty, data.count <= Self.maximumByteCount else { return }
        entries.insert(
            Entry(
                module: package.type,
                itemId: package.id,
                fingerprint: MasterPackageFingerprint(package),
                package: package
            ),
            at: 0
        )
        while entries.count > Self.maximumEntries
            || entries.reduce(0, { $0 + $1.byteCount }) > Self.maximumByteCount {
            entries.removeLast()
        }
    }

    mutating func removeAll() {
        entries.removeAll()
    }
}
