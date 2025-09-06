// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

struct MapModel: Equatable, Hashable, Identifiable, Sendable, Codable {
    init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int, entries: CRDTDataUpdate<[MapEntryModel]>, displayConfig: CRDTDataUpdate<DisplayConfigModel>, photoId: CRDTDataUpdate<UUID?>, width: CGFloat, height: CGFloat, mapPins: CRDTDataUpdate<[MapPinModel]>, pinScale: CGFloat, hexMapScale: CRDT<Double>, scale: CGFloat, degrees: Double) {
        self.id = id
        self.name = name
        self.description = description
        self.tags = tags
        self.category = category
        self.displayState = displayState
        self.entries = entries
        self.displayConfig = displayConfig
        self.photoId = photoId
        self.width = width
        self.height = height
        self.mapPins = mapPins
        self.pinScale = pinScale
        self.hexMapScale = hexMapScale
        self.scale = scale
        self.degrees = degrees
    }

    var id: UUID
    var name: CRDT<String>
    var description: CRDT<String>
    var tags: CRDT<[String]>
    var category: CRDT<ItemListCategory>
    var displayState: Int = 0
    var entries: CRDTDataUpdate<[MapEntryModel]>
    var displayConfig: CRDTDataUpdate<DisplayConfigModel>
    var photoId: CRDTDataUpdate<UUID?>
    var width: CGFloat = 1200
    var height: CGFloat = 800
    var mapPins: CRDTDataUpdate<[MapPinModel]>
    var pinScale: CGFloat = 1.0
    var hexMapScale: CRDT<Double>
    var scale: CGFloat = 1.0
    var pointer: MapPinModel = MapPinModel(id: UUID(), name: "Pointer", color: .red, isShown: false)
    var degrees: Double = 0

    enum CodingKeys: CodingKey {
        case _id
        case _name_
        case _description_
        case _tags_
        case _category_
        case _displayState
        case _entries_
        case _displayConfig_
        case _photoId_
        case _width
        case _height
        case _mapPins_
        case _pinScale
        case _hexMapScale_
        case _scale
        case _degrees
    }

    func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<MapModel.CodingKeys> = encoder.container(keyedBy: MapModel.CodingKeys.self)

        try container.encode(self.id, forKey: MapModel.CodingKeys._id)
        try container.encode(self.name, forKey: MapModel.CodingKeys._name_)
        try container.encode(self.description, forKey: MapModel.CodingKeys._description_)
        try container.encode(self.tags, forKey: MapModel.CodingKeys._tags_)
        try container.encode(self.category, forKey: MapModel.CodingKeys._category_)
        try container.encode(self.displayState, forKey: MapModel.CodingKeys._displayState)
        try container.encode(self.entries, forKey: MapModel.CodingKeys._entries_)
        try container.encode(self.displayConfig, forKey: MapModel.CodingKeys._displayConfig_)
        try container.encode(self.photoId, forKey: MapModel.CodingKeys._photoId_)
        try container.encode(self.width, forKey: MapModel.CodingKeys._width)
        try container.encode(self.height, forKey: MapModel.CodingKeys._height)
        try container.encode(self.mapPins, forKey: MapModel.CodingKeys._mapPins_)
        try container.encode(self.pinScale, forKey: MapModel.CodingKeys._pinScale)
        try container.encode(self.hexMapScale, forKey: MapModel.CodingKeys._hexMapScale_)
        try container.encode(self.scale, forKey: MapModel.CodingKeys._scale)
        try container.encode(self.degrees, forKey: MapModel.CodingKeys._degrees)
    }
    
    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<MapModel.CodingKeys> = try decoder.container(keyedBy: MapModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: MapModel.CodingKeys._id)
        self.name = try container.decode(CRDT<String>.self, forKey: MapModel.CodingKeys._name_)
        self.description = try container.decode(CRDT<String>.self, forKey: MapModel.CodingKeys._description_)
        self.tags = try container.decode(CRDT<[String]>.self, forKey: MapModel.CodingKeys._tags_)
        self.category = try container.decode(CRDT<ItemListCategory>.self, forKey: MapModel.CodingKeys._category_)
        self.displayState = try container.decode(Int.self, forKey: MapModel.CodingKeys._displayState)
        self.entries = try container.decode(CRDTDataUpdate<[MapEntryModel]>.self, forKey: MapModel.CodingKeys._entries_)
        self.displayConfig = try container.decode(CRDTDataUpdate<DisplayConfigModel>.self, forKey: MapModel.CodingKeys._displayConfig_)
        self.photoId = try container.decode(CRDTDataUpdate<UUID?>.self, forKey: MapModel.CodingKeys._photoId_)
        self.width = try container.decode(CGFloat.self, forKey: MapModel.CodingKeys._width)
        self.height = try container.decode(CGFloat.self, forKey: MapModel.CodingKeys._height)
        self.mapPins = try container.decode(CRDTDataUpdate<[MapPinModel]>.self, forKey: MapModel.CodingKeys._mapPins_)
        self.pinScale = try container.decode(CGFloat.self, forKey: MapModel.CodingKeys._pinScale)
        self.hexMapScale = try container.decode(CRDT<Double>.self, forKey: MapModel.CodingKeys._hexMapScale_)
        self.scale = try container.decode(CGFloat.self, forKey: MapModel.CodingKeys._scale)
        self.degrees = try container.decode(Double.self, forKey: MapModel.CodingKeys._degrees)
    }
}

struct MapEntryModel: Identifiable, Equatable, Hashable, Codable, Sendable {
    init(id: UUID, name: CRDT<String>, content: CRDT<String>, coordinates: CRDTDataUpdate<[CGPoint]>, isHexGrid: Bool, isShown: Bool, focused: Bool = false, displayState: Int = 0) {
        self.id = id
        _name = name
        _content = content
        _coordinates = coordinates
        self.isHexGrid = isHexGrid
        self.isShown = isShown
        self.focused = focused
        self.displayState = isHexGrid ? DisplayStateMask.groupHidden.rawValue : 0
    }

    var id: UUID
    @CRDT var name: String
    @CRDT var content: String
    @CRDTDataUpdate var coordinates: [CGPoint]
    var isHexGrid: Bool = false
    var isShown: Bool = false

    var focused: Bool = false
    var displayState: Int = 0

    enum CodingKeys: CodingKey {
        case id
        case name
        case content
        case coordinates
        case isHexGrid
        case isShown
        case focused
        case displayState
    }

    func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<MapEntryModel.CodingKeys> = encoder.container(keyedBy: MapEntryModel.CodingKeys.self)

        try container.encode(self.id, forKey: MapEntryModel.CodingKeys.id)
        try container.encode(self._name, forKey: MapEntryModel.CodingKeys.name)
        try container.encode(self._content, forKey: MapEntryModel.CodingKeys.content)
        try container.encode(self._coordinates, forKey: MapEntryModel.CodingKeys.coordinates)
        try container.encode(self.isHexGrid, forKey: MapEntryModel.CodingKeys.isHexGrid)
        try container.encode(self.isShown, forKey: MapEntryModel.CodingKeys.isShown)
        try container.encode(self.focused, forKey: MapEntryModel.CodingKeys.focused)
        try container.encode(self.displayState, forKey: MapEntryModel.CodingKeys.displayState)
    }
    
    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<MapEntryModel.CodingKeys> = try decoder.container(keyedBy: MapEntryModel.CodingKeys.self)
        
        self.id = try container.decode(UUID.self, forKey: MapEntryModel.CodingKeys.id)
        self._name = try container.decode(CRDT<String>.self, forKey: MapEntryModel.CodingKeys.name)
        self._content = try container.decode(CRDT<String>.self, forKey: MapEntryModel.CodingKeys.content)
        self._coordinates = try container.decode(CRDTDataUpdate<[CGPoint]>.self, forKey: MapEntryModel.CodingKeys.coordinates)
        self.isHexGrid = try container.decodeIfPresent(Bool.self, forKey: MapEntryModel.CodingKeys.isHexGrid) ?? false
        self.isShown = try container.decode(Bool.self, forKey: MapEntryModel.CodingKeys.isShown)
        self.focused = try container.decode(Bool.self, forKey: MapEntryModel.CodingKeys.focused)
        self.displayState = try container.decode(Int.self, forKey: MapEntryModel.CodingKeys.displayState)
    }
}

struct DisplayConfigModel: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    var tileCoordinates: [CGPoint]
    var color: Color = .black
    var border: DisplayBorderViewModel

    var borderColor: Color {
        get { border.color }
        set { border.color = newValue }
    }

    var borderThickness: CGFloat {
        get { border.thickness }
        set { border.thickness = newValue }
    }

    var borderThicknessDouble: Double {
        get { Double(border.thickness) }
        set { border.thickness = CGFloat(newValue) }
    }

    var borderText: String {
        get { String("\(border.thickness)") }
        set {
            let value = Double(newValue) ?? 0
            border.thickness = CGFloat(value)
        }
    }

    var hasBorder: Bool {
        get { borderThickness > 0 }
        set {
            if newValue {
                if borderThickness == 0 {
                    borderThickness = 4
                }
            } else {
                borderThickness = 0
            }
        }
    }
}

extension DisplayConfigModel: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case tileCoordinates
        case color
        case border
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(tileCoordinates, forKey: .tileCoordinates)
        try container.encode(CodableColor(color), forKey: .color)
        try container.encode(border, forKey: .border)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        tileCoordinates = try values.decode([CGPoint].self, forKey: .tileCoordinates)
        let ccolor = try values.decode(CodableColor.self, forKey: .color)
        color = ccolor.color
        border = try values.decode(DisplayBorderViewModel.self, forKey: .border)
    }
}

struct DisplayBorderViewModel: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    var thickness: CGFloat = 0
    var color: Color = .red
}

extension DisplayBorderViewModel: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case thickness
        case color
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(thickness, forKey: .thickness)
        try container.encode(CodableColor(color), forKey: .color)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        thickness = try values.decode(CGFloat.self, forKey: .thickness)
        let ccolor = try values.decode(CodableColor.self, forKey: .color)
        color = ccolor.color
    }
}

struct MapPinModel: Identifiable, Equatable, Hashable, Sendable, Codable {
    init(id: UUID, name: String, color: Color = .red, photoId: UUID? = nil, location: CGPoint = .zero, size: MapPinModel.MapPinSize = .normal, isShown: Bool = true, isPlayer: Bool = false, players: [UUID] = [], timeInterval: TimeInterval = 0) {
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
    
    enum MapPinSize: Int, Identifiable, Hashable, Equatable, Codable, CaseIterable {
        case tiny = 0
        case small = 1
        case normal = 2
        case large = 3
        case huge = 4
        case colossal = 5

        var id: Int {
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

    var id: UUID
    var name: String
    var color: Color = .red
    var photoId: UUID?
    var location: CGPoint = .zero
    var size: MapPinSize = .normal
    var isShown: Bool = true
    var isPlayer: Bool = false
    var players: [UUID] = []
    var timeInterval: TimeInterval = 0

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

    func encode(to encoder: Encoder) throws {
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

    init(from decoder: Decoder) throws {
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
