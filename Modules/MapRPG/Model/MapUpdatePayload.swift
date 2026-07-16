// @copyright André Trettin

import CoreRPG
import CoreGraphics
import CryptoKit
import Foundation

/// Versioned, photo-free map metadata sent through the ordinary chunked
/// messenger path. UUID photo references are present in the snapshot, but no
/// photo bytes or exported dependent-module records are included.
struct MapUpdatePayload: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let snapshot: MapSnapshot
    /// Sender-computed canonical structural fingerprint. Keeping this value in
    /// the payload avoids recalculating it from platform color/CGFloat Codable
    /// representations that may normalize during a round trip.
    let contentVersion: Int

    @MainActor
    init(model: MapModel) {
        let schemaVersion = Self.currentSchemaVersion
        let snapshot = MapSnapshot(model)
        self.schemaVersion = schemaVersion
        self.snapshot = snapshot
        contentVersion = StableMapVersion.digest(
            CanonicalMapContent(schemaVersion: schemaVersion, snapshot: snapshot)
        )
    }

    var isSupported: Bool {
        schemaVersion == Self.currentSchemaVersion
    }

    func encodedData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }

    static func decodeData(_ data: Data?) -> Self? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
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
                canonicalPin.timeInterval = 0
                canonicalPin.isZoom = false
                canonicalPin.players.sort { $0.uuidString < $1.uuidString }
                return canonicalPin
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
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

    init(_ entry: MapEntryModel) {
        id = entry.id
        name = entry.name
        content = entry.content
        coordinates = entry.coordinates
        isHexGrid = entry.isHexGrid
        displayState = entry.displayState
    }
}

struct MapAssetFingerprint: Codable, Sendable {
    static let schemaVersion = 1

    let mapId: UUID
    let backgroundPhotoId: UUID?
    let backgroundPhotoVersion: Int?

    var version: Int {
        StableMapVersion.digest(self)
    }
}

private enum StableMapVersion {
    static func digest<Value: Encodable>(_ value: Value) -> Int {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return -1 }
        let digest = SHA256.hash(data: data)
        let rawValue = digest.prefix(8).reduce(UInt64(0)) { partialResult, byte in
            partialResult << 8 | UInt64(byte)
        }
        return Int(bitPattern: UInt(truncatingIfNeeded: rawValue))
    }
}
