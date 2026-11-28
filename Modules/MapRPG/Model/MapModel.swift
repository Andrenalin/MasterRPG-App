// @copyright André Trettin

import CoreRPG
import CoreGraphics
import Foundation
import SwiftUI

// Split out of this file — see CODE_AUDIT §9.13:
// - MapModel+Geometry.swift: image reset/rotation math, room toggle/focus
// - MapModel+Sync.swift: Comparable, ItemLinkRegistrable, ItemDiffComparable (merge/isSame/version)
// - MapModel+DataAccess.swift: review properties, ItemDuplicatable/ItemDataAccessible
// - MapModel+Codable.swift: Codable, Equatable/Hashable

enum MapPinId {
    case id
}

// MainActor-owned model. Sendable via global-actor isolation (no @unchecked):
// persistence crosses the Core Data boundary as MapSnapshot,
// the .gmz wire format stays on this type's Codable (encode/decode on MainActor).
@MainActor @Observable
public final class MapModel: nonisolated Identifiable {
    nonisolated public init(id: UUID, name: String, description: String = "", tags: [String] = [], category: ItemListCategory = .dungeon, displayState: Int = 0, entries: [MapEntryModel] = [], displayConfig: DisplayConfigModel = DisplayConfigModel(id: UUID(), tileCoordinates: [], border: DisplayBorderViewModel(id: UUID())), photoId: UUID? = nil, width: CGFloat = 1200, height: CGFloat = 800, mapPins: [MapPinModel] = [], walls: [MapWallModel] = [], pinScale: CGFloat = 1.0, hexMapScale: Double = 0, scale: CGFloat = 1.0, degrees: Double = 0, parentId: UUID? = nil, hasRecordedDegrees: Bool = true) {
        self.id = id
        _name_ = CRDT(wrappedValue: name)
        _description_ = CRDT(wrappedValue: description)
        _tags_ = CRDT(wrappedValue: tags)
        _category_ = CRDT(wrappedValue: category)
        self._displayState = displayState
        _entries_ = CRDTDataUpdate(wrappedValue: entries)
        _displayConfig_ = CRDTDataUpdate(wrappedValue: displayConfig)
        _photoId_ = CRDTDataUpdate(wrappedValue: photoId)
        self._width = width
        self._height = height
        _mapPins_ = CRDTDataUpdate(wrappedValue: mapPins)
        _walls_ = CRDTDataUpdate(wrappedValue: walls)
        self._pinScale = pinScale
        _hexMapScale_ = CRDT(wrappedValue: hexMapScale)
        self._scale = scale
        self._degrees = degrees
        self._parentId = parentId
        self._hasRecordedDegrees = hasRecordedDegrees
    }

    nonisolated public init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int, entries: CRDTDataUpdate<[MapEntryModel]>, displayConfig: CRDTDataUpdate<DisplayConfigModel>, photoId: CRDTDataUpdate<UUID?>, width: CGFloat, height: CGFloat, mapPins: CRDTDataUpdate<[MapPinModel]>, walls: CRDTDataUpdate<[MapWallModel]> = CRDTDataUpdate(wrappedValue: []), pinScale: CGFloat, hexMapScale: CRDT<Double>, scale: CGFloat, degrees: Double, parentId: UUID?, hasRecordedDegrees: Bool = true) {
        self.id = id
        _name_ = name
        _description_ = description
        _tags_ = tags
        _category_ = category
        self._displayState = displayState
        _entries_ = entries
        _displayConfig_ = displayConfig
        _photoId_ = photoId
        self._width = width
        self._height = height
        _mapPins_ = mapPins
        _walls_ = walls
        self._pinScale = pinScale
        _hexMapScale_ = hexMapScale
        self._scale = scale
        self._degrees = degrees
        self._parentId = parentId
        self._hasRecordedDegrees = hasRecordedDegrees
    }

    nonisolated public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<MapModel.CodingKeys> = try decoder.container(keyedBy: MapModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: MapModel.CodingKeys._id)
        self._name_ = try container.decode(CRDT<String>.self, forKey: MapModel.CodingKeys._name_)
        self._description_ = try container.decode(CRDT<String>.self, forKey: MapModel.CodingKeys._description_)
        self._tags_ = try container.decode(CRDT<[String]>.self, forKey: MapModel.CodingKeys._tags_)
        self._category_ = try container.decode(CRDT<ItemListCategory>.self, forKey: MapModel.CodingKeys._category_)
        self._displayState = try container.decode(Int.self, forKey: MapModel.CodingKeys._displayState)
        self._entries_ = try container.decode(CRDTDataUpdate<[MapEntryModel]>.self, forKey: MapModel.CodingKeys._entries_)
        self._displayConfig_ = try container.decode(CRDTDataUpdate<DisplayConfigModel>.self, forKey: MapModel.CodingKeys._displayConfig_)
        self._photoId_ = try container.decode(CRDTDataUpdate<UUID?>.self, forKey: MapModel.CodingKeys._photoId_)
        self._width = try container.decode(CGFloat.self, forKey: MapModel.CodingKeys._width)
        self._height = try container.decode(CGFloat.self, forKey: MapModel.CodingKeys._height)
        self._mapPins_ = try container.decode(CRDTDataUpdate<[MapPinModel]>.self, forKey: MapModel.CodingKeys._mapPins_)
        self._walls_ = try container.decodeIfPresent(CRDTDataUpdate<[MapWallModel]>.self, forKey: MapModel.CodingKeys._walls_) ?? CRDTDataUpdate(wrappedValue: [])
        self._pinScale = try container.decode(CGFloat.self, forKey: MapModel.CodingKeys._pinScale)
        self._hexMapScale_ = try container.decode(CRDT<Double>.self, forKey: MapModel.CodingKeys._hexMapScale_)
        self._scale = try container.decode(CGFloat.self, forKey: MapModel.CodingKeys._scale)
        self._degrees = try container.decode(Double.self, forKey: MapModel.CodingKeys._degrees)
        self._parentId = try container.decodeIfPresent(UUID.self, forKey: MapModel.CodingKeys._parentId)
        // A sender that predates the flag never stored its rotation, so its `_degrees` is not a record.
        self._hasRecordedDegrees = try container.decodeIfPresent(Bool.self, forKey: MapModel.CodingKeys._hasRecordedDegrees) ?? false
    }

    // `let`: nonisolated access (Identifiable, hashing) per SE-0434.
    public let id: UUID

    public var name: String {
        get { name_.wrappedValue }
        set { name_.wrappedValue = newValue }
    }
    var name_: CRDT<String>

    public var description: String {
        get { description_.wrappedValue }
        set { description_.wrappedValue = newValue }
    }
    var description_: CRDT<String>

    public var tags: [String] {
        get { tags_.wrappedValue }
        set { tags_.wrappedValue = newValue }
    }
    var tags_: CRDT<[String]>

    public var category: ItemListCategory {
        get { category_.wrappedValue }
        set { category_.wrappedValue = newValue }
    }
    var category_: CRDT<ItemListCategory>

    public var displayState: Int = 0 {
        didSet { resetEntries() }
    }

    public var entries: [MapEntryModel] {
        get { entries_.wrappedValue }
        set { entries_.wrappedValue = newValue }
    }
    var entries_: CRDTDataUpdate<[MapEntryModel]>

    public var displayConfig: DisplayConfigModel {
        get { displayConfig_.wrappedValue }
        set { displayConfig_.wrappedValue = newValue }
    }
    var displayConfig_: CRDTDataUpdate<DisplayConfigModel>

    public var photoId: UUID? {
        get { photoId_.wrappedValue }
        set { photoId_.wrappedValue = newValue }
    }
    var photoId_: CRDTDataUpdate<UUID?>

    public internal(set) var width: CGFloat = 1200
    public internal(set) var height: CGFloat = 800

    public var mapPins: [MapPinModel] {
        get { mapPins_.wrappedValue }
        set { mapPins_.wrappedValue = newValue }
    }
    var mapPins_: CRDTDataUpdate<[MapPinModel]>

    public var walls: [MapWallModel] {
        get { walls_.wrappedValue }
        set { walls_.wrappedValue = newValue }
    }
    var walls_: CRDTDataUpdate<[MapWallModel]>

    public var pinScale: CGFloat = 1.0
    public var hexMapScale: Double {
        get { hexMapScale_.wrappedValue }
        set { hexMapScale_.wrappedValue = newValue }
    }
    var hexMapScale_: CRDT<Double>

    // play infos
    public var scale: CGFloat = 1.0
    public var pointer: MapPinModel = MapPinModel(id: UUID(), name: "Pointer", color: .red, isShown: false)

    var degrees: Double = 0
    /// Whether `degrees` was ever stored with the map. Maps saved before the rotation was persisted
    /// load with `degrees` 0 and `false`; their rooms and pins already follow the photo's rotation,
    /// so the repair adopts the photo's degrees without moving content. See `recordLegacyDegrees`.
    var hasRecordedDegrees: Bool = true

    public var parentId: UUID? = nil
}

// `encode(to:)` reads `@Observable`'s macro-synthesized private backing
// storage (`_name_`, `_description_`, ...) directly, bypassing observation
// tracking — Swift's `private` only extends to same-file extensions, so this
// stays here rather than in MapModel+Codable.swift. See CODE_AUDIT §9.13.
extension MapModel: nonisolated Codable {
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
        case _walls_
        case _pinScale
        case _hexMapScale_
        case _scale
        case _degrees
        case _parentId
        case _hasRecordedDegrees
    }

    nonisolated public final func encode(to encoder: Encoder) throws {
        try encoder.encodeOnMainActor { encoder in
            var container: KeyedEncodingContainer<MapModel.CodingKeys> = encoder.container(keyedBy: MapModel.CodingKeys.self)

            try container.encode(self.id, forKey: MapModel.CodingKeys._id)
            try container.encode(self._name_, forKey: MapModel.CodingKeys._name_)
            try container.encode(self._description_, forKey: MapModel.CodingKeys._description_)
            try container.encode(self._tags_, forKey: MapModel.CodingKeys._tags_)
            try container.encode(self._category_, forKey: MapModel.CodingKeys._category_)
            try container.encode(self._displayState, forKey: MapModel.CodingKeys._displayState)
            try container.encode(self._entries_, forKey: MapModel.CodingKeys._entries_)
            try container.encode(self._displayConfig_, forKey: MapModel.CodingKeys._displayConfig_)
            try container.encode(self._photoId_, forKey: MapModel.CodingKeys._photoId_)
            try container.encode(self._width, forKey: MapModel.CodingKeys._width)
            try container.encode(self._height, forKey: MapModel.CodingKeys._height)
            try container.encode(self._mapPins_, forKey: MapModel.CodingKeys._mapPins_)
            try container.encode(self._walls_, forKey: MapModel.CodingKeys._walls_)
            try container.encode(self._pinScale, forKey: MapModel.CodingKeys._pinScale)
            try container.encode(self._hexMapScale_, forKey: MapModel.CodingKeys._hexMapScale_)
            try container.encode(self._scale, forKey: MapModel.CodingKeys._scale)
            try container.encode(self._degrees, forKey: MapModel.CodingKeys._degrees)
            try container.encodeIfPresent(self._parentId, forKey: MapModel.CodingKeys._parentId)
            try container.encode(self.hasRecordedDegrees, forKey: MapModel.CodingKeys._hasRecordedDegrees)
        }
    }
}

extension MapModel: nonisolated ItemDataAccessible {
    public var fileUrl: FileUrl? {
        get { nil }
        set(newValue) {}
    }

    nonisolated public static var empty: MapModel { empty(UUID()) }
    nonisolated public static func empty(_ id: UUID) -> MapModel {
        MapModel(id: id, name: "")
    }
    nonisolated public static let typeId: NetworkModules = .map
    /// Map content (rooms, links, pins, border, cover, tiles, photo, hex grid) stays in game memory
    /// while a game runs, also from the editor window; only the metadata persists.
    /// See CODE_AUDIT_Edit_Save §5.13.
    nonisolated public static var hasSessionOnlyEntries: Bool { true }

    public func copy() -> MapModel {
        MapModel(id: id, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, entries: entries_, displayConfig: displayConfig_, photoId: photoId_, width: width, height: height, mapPins: mapPins_, walls: walls_, pinScale: pinScale, hexMapScale: hexMapScale_, scale: scale, degrees: degrees, parentId: parentId, hasRecordedDegrees: hasRecordedDegrees)
    }

    public func filter(filter: String, includeEntries: Bool) -> Bool {
        guard !filter.isEmpty else { return true }
        guard !(name.localizedStandardContains(filter) || description.localizedStandardContains(filter)) else { return true }
        guard specialCategory == false else { return false }
        return entries.contains {
            $0.filter(with: filter)
        }
    }

    public func isEqual(other: MapModel) -> Bool {
        self == other
    }

    public var isGroupHiddenToggle: Bool {
        get { isGroupHidden }
        set {
            if newValue {
                displayState = DisplayStateMask.groupHidden.set(on: displayState)
            } else {
                displayState = DisplayStateMask.groupHidden.reset(on: displayState)
            }
        }
    }

    @MainActor public func replace(with model: MapModel) -> Bool {
        guard self != model else { return false }
        name_ <=> model.name_
        description_ <=> model.description_
        tags_ <=> model.tags_
        category_ <=> model.category_
        displayState <=> model.displayState
        entries_ <=> model.entries_
        displayConfig_ <=> model.displayConfig_
        photoId_ <=> model.photoId_
        width <=> model.width
        height <=> model.height
        mapPins_ <=> model.mapPins_
        walls_ <=> model.walls_
        pinScale <=> model.pinScale
        hexMapScale_ <=> model.hexMapScale_
        scale <=> model.scale
        degrees <=> model.degrees
        hasRecordedDegrees <=> model.hasRecordedDegrees
        parentId <=> model.parentId
        return true
    }

    public subscript(id: UUID) -> MapEntryModel {
        get {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return .empty(id) }
            return entries[index]
        }
        set {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index] = newValue
        }
    }
}
