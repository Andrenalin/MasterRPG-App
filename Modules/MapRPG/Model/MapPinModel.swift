// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct MapPinModel: Identifiable, Equatable, Hashable, Sendable {
    public init(id: UUID, name: String, color: Color = .red, photoId: UUID? = nil, characterId: UUID? = nil, location: CGPoint = .zero, size: MapPinSize = .normal, isShown: Bool = true, isPlayer: Bool = false, players: [UUID] = [], timeInterval: TimeInterval = 0, isZoom: Bool = false, isDead: Bool = false, isHighlighted: Bool = false, healthPercent: Double? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.photoId = photoId
        self.characterId = characterId
        self.location = location
        self.size = size
        self.isShown = isShown
        self.isPlayer = isPlayer
        self.players = players
        self.timeInterval = timeInterval
        self.isZoom = isZoom
        self.isDead = isDead
        self.isHighlighted = isHighlighted
        self.healthPercent = healthPercent
    }
    
    public enum MapPinSize: Int, Identifiable, Hashable, Equatable, Codable, CaseIterable, Sendable {
        case tiny = 0
        case small = 1
        case normal = 2
        case large = 3
        case huge = 4
        case colossal = 5

        public var id: Int {
            rawValue
        }

        var text: String {
            switch self {
            case .tiny:
                return "Tiny"
            case .small:
                return "Small"
            case .normal:
                return "Normal"
            case .large:
                return "Large"
            case .huge:
                return "Huge"
            case .colossal:
                return "Colossal"
            }
        }

        /// Base render size in points, before `MapModel.pinScale` and zoom are
        /// applied. Exposed so other renderers (the 3D table) can derive a
        /// pin's on-screen size the same way the 2D map does.
        public var size: CGSize {
            switch self {
            case .tiny:
                return CGSize(width: 22, height: 22)
            case .small:
                return CGSize(width: 36, height: 36)
            case .normal:
                return CGSize(width: 44, height: 44)
            case .large:
                return CGSize(width: 64, height: 64)
            case .huge:
                return CGSize(width: 88, height: 88)
            case .colossal:
                return CGSize(width: 128, height: 128)
            }
        }
        
        func nextSize() -> MapPinSize {
            switch self {
            case .tiny: .small
            case .small: .normal
            case .normal: .large
            case .large: .huge
            case .huge: .colossal
            case .colossal: .tiny
            }
        }
    }

    public var id: UUID
    public var name: String
    public var color: Color = .red
    public var photoId: UUID?
    public var characterId: UUID?
    public var location: CGPoint = .zero
    public var size: MapPinSize = .normal
    public var isShown: Bool = true
    public var isPlayer: Bool = false
    public var players: [UUID] = []
    public var timeInterval: TimeInterval = 0
    public var isZoom: Bool = false
    public var isDead: Bool = false
    public var isHighlighted: Bool = false
    /// 0...100 health reading derived from the combatant's linked hit-points
    /// entry. `nil` means no entry is linked (or the battle never computed
    /// one yet), which the border renders as neutral grey.
    public var healthPercent: Double?
}

extension MapPinModel: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case photoId
        case characterId
        case location
        case size
        case isShown
        case isPlayer
        case players
        case timeInterval
        case isZoom
        case isDead
        case isHighlighted
        case healthPercent
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(location, forKey: .location)
        try container.encode(CodableColor(color), forKey: .color)
        try container.encode(photoId, forKey: .photoId)
        try container.encode(characterId, forKey: .characterId)
        try container.encode(size, forKey: .size)
        try container.encode(isShown, forKey: .isShown)
        try container.encode(isPlayer, forKey: .isPlayer)
        try container.encode(players, forKey: .players)
        try container.encode(timeInterval, forKey: .timeInterval)
        try container.encode(isZoom, forKey: .isZoom)
        try container.encode(isDead, forKey: .isDead)
        try container.encode(isHighlighted, forKey: .isHighlighted)
        try container.encodeIfPresent(healthPercent, forKey: .healthPercent)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        location = try values.decode(CGPoint.self, forKey: .location)
        let ccolor = try values.decode(CodableColor.self, forKey: .color)
        color = ccolor.color
        photoId = try values.decodeIfPresent(UUID.self, forKey: .photoId)
        characterId = try values.decodeIfPresent(UUID.self, forKey: .characterId)
        size = try values.decode(MapPinSize.self, forKey: .size)
        isShown = try values.decode(Bool.self, forKey: .isShown)
        isPlayer = try values.decodeIfPresent(Bool.self, forKey: .isPlayer) ?? false
        players = try values.decode([UUID].self, forKey: .players)
        timeInterval = try values.decode(TimeInterval.self, forKey: .timeInterval)
        isZoom = try values.decodeIfPresent(Bool.self, forKey: .isZoom) ?? false
        isDead = try values.decodeIfPresent(Bool.self, forKey: .isDead) ?? false
        isHighlighted = try values.decodeIfPresent(Bool.self, forKey: .isHighlighted) ?? false
        healthPercent = try values.decodeIfPresent(Double.self, forKey: .healthPercent)
    }
}

extension MapPinModel {
    /// Border color reflecting the pin's last *broadcast* health reading: red
    /// under 50%, orange under 80%, green from 80% up. `nil` (no hit-points
    /// entry linked yet) renders as neutral grey — the pin's prior default.
    ///
    /// This is the persisted/networked snapshot, refreshed only when the map
    /// pushes an update (see `GameController.synchronizeBattleDefenders`) —
    /// the only source available to a player, who has no access to the
    /// linked Character. `MapPinView` prefers a live-computed percent instead
    /// whenever the pin is a tracked combatant, so the game master's own
    /// screen updates instantly with the source entry rather than waiting for
    /// the next push. Both paths render through `healthBorderColor(for:)`.
    var healthBorderColor: Color { Self.healthBorderColor(for: healthPercent) }

    static func healthBorderColor(for healthPercent: Double?) -> Color {
        guard let healthPercent else { return .gray }
        return switch healthPercent {
        case ..<50: .red
        case 50..<80: .orange
        default: .green
        }
    }
}

extension MapPinModel {
    public static let typeId: NetworkModules = .map
    public static var empty: MapPinModel {
        empty(UUID())
    }

    public static func empty(_ id: UUID) -> MapPinModel {
        MapPinModel(id: id, name: "")
    }

    public func filter(_ filter: String, selectedTags _: [TagFilterSelection]) -> Bool {
        filter.isEmpty || name.localizedCaseInsensitiveContains(filter)
    }
}

extension MapPinModel: ItemDuplicatable {
    public func duplicate() -> MapPinModel {
        var dup = self
        dup.id = UUID()
        return dup
    }
}

extension MapPinModel: MessageMapper {}
