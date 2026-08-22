// @copyright André Trettin

import CoreRPG
import CoreGraphics
import Foundation

/// Public so the 3D table (GameRPG, a separate module) can hold and cycle its
/// own `displayMode` to satisfy `GameToolBarSession` — the same shared-toolbar
/// preview mode the 2D map already offers.
public enum MapDisplayMode: Int, Identifiable, Equatable, Hashable, CaseIterable, Sendable {
    case master = 0
    case player = 1
    case reader = 2

    public var id: Int {
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

public struct MapEntryModel: Identifiable, Equatable, Hashable, Codable, Sendable {
    public init(id: UUID, name: String, content: String, coordinates: [CGPoint], isHexGrid: Bool = false, isShown: Bool = false, focused: Bool = false, displayState: Int = 0) {
        self.id = id
        self.name = name
        self.content = content
        self.coordinates = coordinates
        self.isHexGrid = isHexGrid
        self.isShown = isShown
        self.focused = focused
        self.displayState = displayState
    }

    public init(id: UUID, name: CRDT<String>, content: CRDT<String>, coordinates: CRDTDataUpdate<[CGPoint]>, isHexGrid: Bool, isShown: Bool) {
        self.id = id
        _name = name
        _content = content
        _coordinates = coordinates
        self.isHexGrid = isHexGrid
        self.isShown = isShown
        self.focused = false
        self.displayState = isHexGrid ? DisplayStateMask.groupHidden.rawValue : 0
    }

    public var id: UUID
    @CRDT public var name: String
    @CRDT public var content: String
    @CRDTDataUpdate public var coordinates: [CGPoint]
    public var isHexGrid: Bool = false
    public var isShown: Bool = false

    public var focused: Bool = false
    public var displayState: Int = 0

    public init(from decoder: Decoder) throws {
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

public extension MapEntryModel {
    /// Whether the room polygon spanned by `coordinates` contains the point.
    func contains(_ point: CGPoint) -> Bool {
        guard coordinates.count >= 3 else { return false }
        let path = CGMutablePath()
        path.addLines(between: coordinates)
        path.closeSubpath()
        return path.contains(point)
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
    public var childId: UUID { id }
    public static func newChild(id: UUID) -> Self {
        empty(id)
    }

    public static var empty: MapEntryModel {
        empty(UUID())
    }

    public static func empty(_ id: UUID) -> MapEntryModel {
        MapEntryModel(id: id, name: "", content: "", coordinates: [])
    }

    public func duplicate() -> MapEntryModel {
        MapEntryModel(id: UUID(), name: name, content: content, coordinates: coordinates, isHexGrid: isHexGrid, isShown: isShown, focused: focused, displayState: displayState)
    }

    public func filter(with search: String) -> Bool {
        (search.isEmpty || name.localizedStandardContains(search) || content.localizedStandardContains(search))
    }
    
    public func linkContent() -> String { content }
}

extension MapEntryModel: ItemLinkEditable {
    public var textLinkContent: String {
        content
    }
}

extension MapEntryModel: ItemDiffComparable {
    public func merge(_ other: MapEntryModel) -> MapEntryModel {
        MapEntryModel(
            id: id,
            name: $name.merged(other: other.$name),
            content: $content.merged(other: other.$content),
            coordinates: $coordinates.merged(other: other.$coordinates),
            isHexGrid: other.isHexGrid,
            isShown: other.isShown
        )
    }

    public func isSame(_ other: MapEntryModel) -> Bool {
        name == other.name &&
        content == other.content &&
        coordinates == other.coordinates &&
        isHexGrid == other.isHexGrid &&
        isShown == other.isShown
    }
}

extension MapEntryModel: ItemReferencable {}

#if DEBUG
extension MapEntryModel {
    /// Creates a test fixture with sensible defaults for testing.
    ///
    /// All parameters have default values, allowing you to specify only what matters for your test:
    /// ```swift
    /// let entry = MapEntryModel.fixture(name: "Test Map", coordinates: [CGPoint(x: 0, y: 0)])
    /// ```
    public static func fixture(
        id: UUID = UUID(),
        name: String = "Test Map Entry",
        content: String = "Test map content",
        coordinates: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)],
        isHexGrid: Bool = false,
        isShown: Bool = false,
        focused: Bool = false,
        displayState: Int = 0
    ) -> MapEntryModel {
        MapEntryModel(
            id: id,
            name: name,
            content: content,
            coordinates: coordinates,
            isHexGrid: isHexGrid,
            isShown: isShown,
            focused: focused,
            displayState: displayState
        )
    }
}
#endif

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

    public func encode(to encoder: Encoder) throws {
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
