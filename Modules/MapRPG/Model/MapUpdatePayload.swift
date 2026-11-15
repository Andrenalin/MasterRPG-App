// @copyright André Trettin

import CoreRPG
import CoreGraphics
import Foundation

/// Versioned, photo-free map metadata sent through the ordinary chunked
/// messenger path. UUID photo references are present in the snapshot for
/// shown pins, but no photo bytes or exported dependent-module records are
/// included. Hidden-room name and content are stripped and hidden pins are left
/// out entirely before this leaves the sender — see
/// `MapSnapshot.redactedForNonMaster()`.
struct MapUpdatePayload: Codable, Sendable, MessageMapper {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let snapshot: MapSnapshot
    /// Sender-computed canonical structural fingerprint. Keeping this value in
    /// the payload avoids recalculating it from platform color/CGFloat Codable
    /// representations that may normalize during a round trip.
    let contentVersion: Int

    /// This payload only ever travels the live game-sync wire (see the
    /// doc comment on `MapSnapshot`), so its snapshot is always redacted for
    /// a non-master recipient — see CODE_AUDIT §6.1. `contentVersion` is
    /// still computed from the true, unredacted content: the fingerprint
    /// must reflect the master's real map state (including hidden-content
    /// edits) so a later reveal still registers as a version change.
    @MainActor
    init(model: MapModel) {
        let schemaVersion = Self.currentSchemaVersion
        let fullSnapshot = MapSnapshot(model)
        self.schemaVersion = schemaVersion
        snapshot = fullSnapshot.redactedForNonMaster()
        contentVersion = StableVersionDigest.digest(
            CanonicalMapContent(schemaVersion: schemaVersion, snapshot: fullSnapshot)
        )
    }

    /// The content version of `model`, the same value `init(model:)` stores, without building
    /// the redacted snapshot or any payload. Callers that only compare versions (generation
    /// lookups, metadata checks) used to build the whole payload for it. See CODE_AUDIT_26 §7.13.
    @MainActor
    static func contentVersion(of model: MapModel) -> Int {
        StableVersionDigest.digest(
            CanonicalMapContent(schemaVersion: currentSchemaVersion, snapshot: MapSnapshot(model))
        )
    }

    var isSupported: Bool {
        schemaVersion == Self.currentSchemaVersion
    }

    /// Deterministic key ordering, unlike `MessageMapper`'s default encoding —
    /// this payload's byte representation is compared/diffed across sends, so
    /// stable ordering matters here in a way it doesn't for the other
    /// conformers. `decodeData(of:)` has no such requirement and uses the
    /// protocol's default.
    func encodeData() -> Data? {
        try? JSONCoding.sortedKeysEncoder.encode(self)
    }
}

private struct CanonicalMapContent: Codable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let name: String
    let description: String
    let tags: [String]
    let category: ItemListCategory
    let displayState: Int
    let entries: [CanonicalMapEntry]
    let displayConfig: DisplayConfigModel
    let photoId: UUID?
    let width: CGFloat
    let height: CGFloat
    let mapPins: [MapPinModel]
    let walls: [MapWallModel]
    let pinScale: CGFloat
    let hexMapScale: Double
    let scale: CGFloat
    let degrees: Double
    let parentId: UUID?

    init(schemaVersion: Int, snapshot: MapSnapshot) {
        self.schemaVersion = schemaVersion
        id = snapshot.id
        name = snapshot.name.wrappedValue
        description = snapshot.description.wrappedValue
        tags = snapshot.tags.wrappedValue
        category = snapshot.category.wrappedValue
        displayState = snapshot.displayState
        entries = snapshot.entries.wrappedValue.map(CanonicalMapEntry.init)
        displayConfig = snapshot.displayConfig.wrappedValue
        photoId = snapshot.photoId.wrappedValue
        width = snapshot.width
        height = snapshot.height
        mapPins = snapshot.mapPins.wrappedValue
            .map { pin in
                var canonicalPin = pin
                canonicalPin.location = .zero
                canonicalPin.isShown = false
                canonicalPin.size = .normal
                canonicalPin.timeInterval = 0
                canonicalPin.isPhotoShared = false
                canonicalPin.isDead = false
                canonicalPin.isHighlighted = false
                // healthPercent is session-only battle-round state, recomputed
                // every attacker/round advance — it must not perturb the
                // structural fingerprint any more than the other runtime
                // fields above do. See CODE_AUDIT_Game §5.2.
                canonicalPin.healthPercent = nil
                canonicalPin.players.sort { $0.uuidString < $1.uuidString }
                return canonicalPin
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        walls = snapshot.walls.wrappedValue.sorted { $0.id.uuidString < $1.id.uuidString }
        pinScale = snapshot.pinScale
        hexMapScale = snapshot.hexMapScale.wrappedValue
        scale = snapshot.scale
        degrees = snapshot.degrees
        parentId = snapshot.parentId
    }
}

private struct CanonicalMapEntry: Codable, Sendable {
    let id: UUID
    let name: String
    let content: String
    let coordinates: [CGPoint]
    let isHexGrid: Bool
    let displayState: Int
    /// Whether the room is revealed. Players get a hidden room's name and text blanked, so a
    /// reveal must change the fingerprint to make the master resend them. See CODE_AUDIT_23 §5.2.
    let isShown: Bool

    init(_ entry: MapEntryModel) {
        id = entry.id
        name = entry.name
        content = entry.content
        coordinates = entry.coordinates
        isHexGrid = entry.isHexGrid
        displayState = entry.displayState
        isShown = entry.isShown
    }
}

struct MapAssetFingerprint: Codable, Sendable {
    static let schemaVersion = 1

    let mapId: UUID
    let backgroundPhotoId: UUID?
    let backgroundPhotoVersion: Int?

    var version: Int {
        StableVersionDigest.digest(self)
    }
}
