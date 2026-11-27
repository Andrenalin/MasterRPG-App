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

    /// Whether the two room polygons share an area: an edge of one crosses an edge of the other,
    /// or one lies inside the other. Polygons that only touch along a border do not overlap.
    /// See CODE_AUDIT_29 §6.2.
    func overlaps(_ other: MapEntryModel) -> Bool {
        let own = coordinates
        let others = other.coordinates
        guard own.count >= 3, others.count >= 3,
              let ownBounds = own.bounds, let otherBounds = others.bounds,
              ownBounds.intersects(otherBounds) else { return false }
        for index in own.indices {
            let a = own[index], b = own[(index + 1) % own.count]
            for otherIndex in others.indices {
                let c = others[otherIndex], d = others[(otherIndex + 1) % others.count]
                if Self.segmentsCross(a, b, c, d) { return true }
            }
        }
        // No crossing edges: either disjoint or one inside the other. A vertex on the other's
        // border is not inside, so test the centroids too (a cell that exactly fills a room).
        return own.contains(where: { other.containsStrictly($0) })
            || others.contains(where: { containsStrictly($0) })
            || other.containsStrictly(Self.centroid(of: own))
            || containsStrictly(Self.centroid(of: others))
    }

    /// Inside and not on the border.
    private func containsStrictly(_ point: CGPoint) -> Bool {
        guard contains(point) else { return false }
        for index in coordinates.indices {
            let a = coordinates[index], b = coordinates[(index + 1) % coordinates.count]
            if Self.cross(a, b, point) == 0,
               point.x >= min(a.x, b.x), point.x <= max(a.x, b.x),
               point.y >= min(a.y, b.y), point.y <= max(a.y, b.y) {
                return false
            }
        }
        return true
    }

    /// A proper crossing: each segment's ends lie strictly on both sides of the other.
    private static func segmentsCross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        let d1 = cross(c, d, a), d2 = cross(c, d, b)
        let d3 = cross(a, b, c), d4 = cross(a, b, d)
        return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }

    private static func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    private static func centroid(of points: [CGPoint]) -> CGPoint {
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }
}

extension MapEntryModel {
    private var boundingBox: CGRect? { coordinates.bounds }

    var xOffset: CGFloat { boundingBox?.minX ?? 0 }
    var yOffset: CGFloat { boundingBox?.minY ?? 0 }
    var height: CGFloat { boundingBox?.maxY ?? 0 }
    var width: CGFloat { boundingBox?.maxX ?? 0 }

    var size: CGSize {
        let w = width - xOffset
        let h = height - yOffset
        return CGSize(width: w, height: h)
    }

    /// The middle of the room's bounding box, in canvas coordinates.
    var center: CGPoint {
        CGPoint(x: xOffset + size.width / 2, y: yOffset + size.height / 2)
    }

    var rect: CGRect {
        CGRect(origin: CGPoint(x: xOffset, y: yOffset) - 25, size: size + 25)
    }

    /// The room with 25 points of margin on every side, for the thumbnail crop: the origin moves
    /// up-left by the margin, so the size grows by it twice. `rect` stays as it was because the
    /// hex-grid toggle and the pin counter read it. See CODE_AUDIT_22a §5.2.
    var thumbnailRect: CGRect {
        CGRect(origin: CGPoint(x: xOffset, y: yOffset) - 25, size: size + 50)
    }
}

extension MapEntryModel: EntryDataAccessible {
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
