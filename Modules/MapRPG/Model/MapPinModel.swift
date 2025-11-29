// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct MapPinModel: Identifiable, Equatable, Hashable {
    public init(id: UUID, name: String, color: Color = .red, photoId: UUID? = nil, location: CGPoint = .zero, size: MapPinSize = .normal, isShown: Bool = true, isPlayer: Bool = false, players: [UUID] = [], timeInterval: TimeInterval = 0) {
        self.id = id
        self.name = name
        self.color = color
        self.photoId = photoId
        self.location = location
        self.size = size
        self.isShown = isShown
        self.isPlayer = isPlayer
        self.players = players
        self.timeInterval = timeInterval
    }
    
    public enum MapPinSize: Int, Identifiable, Hashable, Equatable, Codable, CaseIterable {
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

        var size: CGSize {
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
    }

    public var id: UUID
    public var name: String
    public var color: Color = .red
    public var photoId: UUID?
    public var location: CGPoint = .zero
    public var size: MapPinSize = .normal
    public var isShown: Bool = true
    public var isPlayer: Bool = false
    public var players: [UUID] = []
    public var timeInterval: TimeInterval = 0
}

extension MapPinModel: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case photoId
        case location
        case size
        case isShown
        case isPlayer
        case players
        case timeInterval
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(location, forKey: .location)
        try container.encode(CodableColor(color), forKey: .color)
        try container.encode(photoId, forKey: .photoId)
        try container.encode(size, forKey: .size)
        try container.encode(isShown, forKey: .isShown)
        try container.encode(isPlayer, forKey: .isPlayer)
        try container.encode(players, forKey: .players)
        try container.encode(timeInterval, forKey: .timeInterval)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        location = try values.decode(CGPoint.self, forKey: .location)
        let ccolor = try values.decode(CodableColor.self, forKey: .color)
        color = ccolor.color
        photoId = try values.decodeIfPresent(UUID.self, forKey: .photoId)
        size = try values.decode(MapPinSize.self, forKey: .size)
        isShown = try values.decode(Bool.self, forKey: .isShown)
        isPlayer = try values.decodeIfPresent(Bool.self, forKey: .isPlayer) ?? false
        players = try values.decode([UUID].self, forKey: .players)
        timeInterval = try values.decode(TimeInterval.self, forKey: .timeInterval)
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

extension MapPinModel {
    static func decodeData(of data: Data?) -> MapPinModel? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(MapPinModel.self, from: data)
    }

    func encodeData() -> Data? {
        let encoder = JSONEncoder()
        return try? encoder.encode(self)
    }
}
