// @copyright André Trettin

import AndrenalinKit
import CoreGraphics
import Foundation

enum MapDisplayMode: Int, Identifiable, Equatable, Hashable, CaseIterable {
    case master = 0
    case player = 1
    case reader = 2

    var id: Int {
        rawValue
    }

    var text: String {
        switch self {
        case .master:
            return "Master"
        case .player:
            return "Player"
        case .reader:
            return "Reader"
        }
    }
}

struct MapEntryModel: Identifiable, Equatable, Hashable, Codable, @unchecked Sendable {
    init(id: UUID, name: String, content: String, coordinates: [CGPoint], isHexGrid: Bool = false, isShown: Bool = false, focused: Bool = false, displayState: Int = 0) {
        self.id = id
        self.name = name
        self.content = content
        self.coordinates = coordinates
        self.isHexGrid = isHexGrid
        self.isShown = isShown
        self.focused = focused
        self.displayState = displayState
    }

    init(id: UUID, name: CRDT<String>, content: CRDT<String>, coordinates: CRDTDataUpdate<[CGPoint]>, isHexGrid: Bool, isShown: Bool) {
        self.id = id
        _name = name
        _content = content
        _coordinates = coordinates
        self.isHexGrid = isHexGrid
        self.isShown = isShown
        self.focused = false
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

extension MapEntryModel {
    var xOffset: CGFloat {
        var x: CGFloat = coordinates.first?.x ?? 0.0
        coordinates.forEach { x = min($0.x, x) }
        return x
    }

    var yOffset: CGFloat {
        var y: CGFloat = coordinates.first?.y ?? 0.0
        coordinates.forEach { y = min($0.y, y) }
        return y
    }

    var height: CGFloat {
        var y: CGFloat = coordinates.first?.y ?? 0.0
        coordinates.forEach { y = max($0.y, y) }
        return y
    }

    var width: CGFloat {
        var x: CGFloat = coordinates.first?.x ?? 0.0
        coordinates.forEach { x = max($0.x, x) }
        return x
    }

    var size: CGSize {
        let w = width - xOffset
        let h = height - yOffset
        return CGSize(width: w, height: h)
    }

    var center: CGPoint {
        CGPoint(x: xOffset - size.width / 2, y: yOffset - size.height / 2)
    }

    var rect: CGRect {
        CGRect(origin: CGPoint(x: xOffset, y: yOffset) - 25, size: size + 25)
    }
}

extension MapEntryModel: EntryDataAccessable {
    static var empty: MapEntryModel {
        empty(UUID())
    }

    static func empty(_ id: UUID) -> MapEntryModel {
        MapEntryModel(id: id, name: "", content: "", coordinates: [])
    }

    func duplicate() -> MapEntryModel {
        MapEntryModel(id: UUID(), name: name, content: content, coordinates: coordinates, isHexGrid: isHexGrid, isShown: isShown, focused: focused, displayState: displayState)
    }

    func filter(with search: String) -> Bool {
        (search.isEmpty || name.localizedCaseInsensitiveContains(search) || content.localizedCaseInsensitiveContains(search))
    }
    
    func linkContent() -> String { content }
}

extension MapEntryModel: ItemLinkEditable {
    var textLinkContent: String {
        content
    }
}

extension MapEntryModel: ItemDiffComparable {
    func merge(_ other: MapEntryModel) -> MapEntryModel {
        MapEntryModel(
            id: id,
            name: $name.merged(other: other.$name),
            content: $content.merged(other: other.$content),
            coordinates: $coordinates.merged(other: other.$coordinates),
            isHexGrid: other.isHexGrid,
            isShown: other.isShown
        )
    }

    func isSame(_ other: MapEntryModel) -> Bool {
        name == other.name &&
        content == other.content &&
        coordinates == other.coordinates &&
        isHexGrid == other.isHexGrid &&
        isShown == other.isShown
    }
}

extension MapEntryModel: ItemReferencable {}

extension MapEntryModel {
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
}
