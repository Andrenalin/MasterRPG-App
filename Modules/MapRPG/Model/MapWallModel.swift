// @copyright André Trettin

import CoreGraphics
import CoreRPG
import Foundation

/// A map-local barrier imported from a virtual tabletop scene.
///
/// Restriction values intentionally preserve their integer representation. Foundry has changed
/// some constants between releases, and an import must not discard a value introduced by a newer
/// version. The named constants describe the current Foundry values while arbitrary raw values
/// continue to round-trip.
public struct MapWallModel: Codable, Equatable, Identifiable, Sendable {
    public struct MovementRestriction: RawRepresentable, Codable, Equatable, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let none = Self(rawValue: 0)
        public static let normal = Self(rawValue: 20)
        public static let legacyNormal = Self(rawValue: 1)
    }

    public struct SightRestriction: RawRepresentable, Codable, Equatable, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let none = Self(rawValue: 0)
        public static let limited = Self(rawValue: 10)
        public static let normal = Self(rawValue: 20)
        public static let proximity = Self(rawValue: 30)
        public static let distance = Self(rawValue: 40)
    }

    public struct DoorType: RawRepresentable, Codable, Equatable, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let none = Self(rawValue: 0)
        public static let door = Self(rawValue: 1)
        public static let secret = Self(rawValue: 2)
    }

    public struct DoorState: RawRepresentable, Codable, Equatable, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let closed = Self(rawValue: 0)
        public static let open = Self(rawValue: 1)
        public static let locked = Self(rawValue: 2)
    }

    public let id: UUID
    public let sourceIdentifier: String
    public var start: CGPoint
    public var end: CGPoint
    public var movementRestriction: MovementRestriction
    public var sightRestriction: SightRestriction
    public var doorType: DoorType
    public var doorState: DoorState
    public var minimumElevation: Double?
    public var maximumElevation: Double?
    public var levelIdentifier: String?
    public var rawMetadata: FoundryJSONValue?

    public init(
        id: UUID? = nil,
        sourceIdentifier: String,
        start: CGPoint,
        end: CGPoint,
        movementRestriction: MovementRestriction = .normal,
        sightRestriction: SightRestriction = .normal,
        doorType: DoorType = .none,
        doorState: DoorState = .closed,
        minimumElevation: Double? = nil,
        maximumElevation: Double? = nil,
        levelIdentifier: String? = nil,
        rawMetadata: FoundryJSONValue? = nil
    ) {
        self.id = id ?? Self.deterministicID(for: sourceIdentifier)
        self.sourceIdentifier = sourceIdentifier
        self.start = start
        self.end = end
        self.movementRestriction = movementRestriction
        self.sightRestriction = sightRestriction
        self.doorType = doorType
        self.doorState = doorState
        self.minimumElevation = minimumElevation
        self.maximumElevation = maximumElevation
        self.levelIdentifier = levelIdentifier
        self.rawMetadata = rawMetadata
    }

    /// Stable across repeated imports when the caller supplies the same canonical source key.
    public static func deterministicID(for sourceIdentifier: String) -> UUID {
        FoundryRuleIdentity.uuid(for: "map-wall:\(sourceIdentifier)")
    }
}

/// One self-describing Core Data value keeps wall persistence lightweight while retaining the
/// CRDT update marker used by map synchronization.
struct PersistedMapWalls: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let walls: CRDTDataUpdate<[MapWallModel]>

    init(
        formatVersion: Int = Self.currentFormatVersion,
        walls: CRDTDataUpdate<[MapWallModel]>
    ) {
        self.formatVersion = formatVersion
        self.walls = walls
    }
}

enum MapWallPersistenceCodec {
    static func decode(_ text: String?) -> CRDTDataUpdate<[MapWallModel]> {
        guard let text, !text.isEmpty, let data = text.data(using: .utf8) else {
            return CRDTDataUpdate(wrappedValue: [])
        }

        let decoder = JSONDecoder()
        if let payload = try? decoder.decode(PersistedMapWalls.self, from: data) {
            return payload.walls
        }
        if let legacyWalls = try? decoder.decode(CRDTDataUpdate<[MapWallModel]>.self, from: data) {
            return legacyWalls
        }
        if let legacyWalls = try? decoder.decode([MapWallModel].self, from: data) {
            return CRDTDataUpdate(wrappedValue: legacyWalls)
        }
        return CRDTDataUpdate(wrappedValue: [])
    }

    static func encode(_ walls: CRDTDataUpdate<[MapWallModel]>) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(PersistedMapWalls(walls: walls)) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
