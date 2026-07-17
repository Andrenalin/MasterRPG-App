// @copyright André Trettin

import CoreRPG
import CoreGraphics
import Foundation
import SwiftUI

enum MapPinId {
    case id
}

// MainActor-owned model. Sendable via global-actor isolation (no @unchecked):
// persistence crosses the Core Data boundary as MapSnapshot,
// the .gmz wire format stays on this type's Codable (encode/decode on MainActor).
@MainActor @Observable
public final class MapModel: nonisolated Identifiable {
    nonisolated public init(id: UUID, name: String, description: String = "", tags: [String] = [], category: ItemListCategory = .dungeon, displayState: Int = 0, entries: [MapEntryModel] = [], displayConfig: DisplayConfigModel = DisplayConfigModel(id: UUID(), tileCoordinates: [], border: DisplayBorderViewModel(id: UUID())), photoId: UUID? = nil, width: CGFloat = 1200, height: CGFloat = 800, mapPins: [MapPinModel] = [], pinScale: CGFloat = 1.0, hexMapScale: Double = 0, scale: CGFloat = 1.0, degrees: Double = 0, parentId: UUID? = nil) {
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
        self._pinScale = pinScale
        _hexMapScale_ = CRDT(wrappedValue: hexMapScale)
        self._scale = scale
        self._degrees = degrees
        self._parentId = parentId
    }

    nonisolated public init(id: UUID, name: CRDT<String>, description: CRDT<String>, tags: CRDT<[String]>, category: CRDT<ItemListCategory>, displayState: Int, entries: CRDTDataUpdate<[MapEntryModel]>, displayConfig: CRDTDataUpdate<DisplayConfigModel>, photoId: CRDTDataUpdate<UUID?>, width: CGFloat, height: CGFloat, mapPins: CRDTDataUpdate<[MapPinModel]>, pinScale: CGFloat, hexMapScale: CRDT<Double>, scale: CGFloat, degrees: Double, parentId: UUID?) {
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
        self._pinScale = pinScale
        _hexMapScale_ = hexMapScale
        self._scale = scale
        self._degrees = degrees
        self._parentId = parentId
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
        self._pinScale = try container.decode(CGFloat.self, forKey: MapModel.CodingKeys._pinScale)
        self._hexMapScale_ = try container.decode(CRDT<Double>.self, forKey: MapModel.CodingKeys._hexMapScale_)
        self._scale = try container.decode(CGFloat.self, forKey: MapModel.CodingKeys._scale)
        self._degrees = try container.decode(Double.self, forKey: MapModel.CodingKeys._degrees)
        self._parentId = try container.decodeIfPresent(UUID.self, forKey: MapModel.CodingKeys._parentId)
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
    
    public var parentId: UUID? = nil
}

public extension MapModel {
    /// Whether players see fog at this location: true when a hidden room
    /// polygon covers it. Locations outside every room are visible (no fog).
    func isLocationHiddenForPlayers(_ location: CGPoint) -> Bool {
        entries.contains { !$0.isShown && $0.contains(location) }
    }
}

extension MapModel {
    subscript(_: MapPinId, positionId: MapPinModel.ID) -> MapPinModel {
        get {
            guard let index = mapPins.firstIndex(where: { $0.id == positionId }) else { return .empty(positionId) }
            return mapPins[index]
        }
        set {
            guard let index = mapPins.firstIndex(where: { $0.id == positionId }) else { return }
            mapPins[index] = newValue
        }
    }
    
    func setPinPointer(updatedPin: MapPinModel) {
        if pointer.id == updatedPin.id {
            pointer = updatedPin
        } else if let index = mapPins.firstIndex(where: { $0.id == updatedPin.id }) {
            mapPins[index] = updatedPin
        }
    }

    func resetImage(with photoId: UUID, size: CGSize, degrees: Double) {
        self.photoId <=> photoId
        guard size.width != width || size.height != height || degrees != self.degrees else { return }
        let oldWidth = width
        let oldHeight = height
        if degrees == 0.0 || degrees == 180.0 {
            width = size.width
            height = size.height
        } else {
            width = size.height
            height = size.width
        }
        self.degrees = degrees
        resetEntrySize(oldWidth: oldWidth, oldHeight: oldHeight)
    }

    func resetEntrySize(oldWidth: Double, oldHeight: Double) {
        guard oldWidth != 0 && oldHeight != 0 else { return }
        var wf = 1.0
        var hf = 1.0
        if oldWidth != width {
            wf = width / oldWidth
        }
        if oldHeight != height {
            hf = height / oldHeight
        }

        guard wf != 1.0 || hf != 1.0 else { return }

        entries = entries.map {
            var replacedEntry = $0
            replacedEntry.coordinates = replacedEntry.coordinates.map {
                CGPoint(x: $0.x * wf, y: $0.y * hf)
            }
            return replacedEntry
        }
        mapPins = mapPins.map {
            var updatedPin = $0
            updatedPin.location = CGPoint(x: updatedPin.location.x * wf, y: updatedPin.location.y * hf)
            return updatedPin
        }
        pointer.location = CGPoint(
            x: pointer.location.x * wf,
            y: pointer.location.y * hf
        )
        var updatedDisplayConfig = displayConfig
        updatedDisplayConfig.tileCoordinates = updatedDisplayConfig.tileCoordinates.map {
            CGPoint(x: $0.x * wf, y: $0.y * hf)
        }
        displayConfig = updatedDisplayConfig
    }

    func toggle(_ entryId: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryId }) else {
            return
        }
        let entry = entries[index]
        if entry.isHexGrid && !entry.isShown {
            let source = entry.rect
            let others = entries.filter { !$0.isHexGrid && !$0.isShown }
            let stories = others.filter { $0.rect.intersects(source) }
            stories.forEach { story in
                guard let storyIndex = entries.firstIndex(where: { $0.id == story.id }) else { return }
                entries[storyIndex].isShown = true
            }
        }
        entries[index].isShown.toggle()
    }

    func focused(_ entry: MapEntryModel) {
        entries.enumerated().forEach { index, sub in
            if entry.id == sub.id {
                entries[index].focused = !entries[index].focused
            } else {
                entries[index].focused = false
            }
        }
    }

    var mapIdealSize: CGSize {
        CGSize(width: width + 100, height: height + 100)
    }

    var children: [MapModel] {
        [self]
    }

    func resetEntries() {
        // Inline isHidden: the protocol convenience is @MainActor; this nonisolated
        // model reads its concrete stored property directly (called from didSet).
        if displayState == DisplayStateMask.totalHidden.rawValue {
            entries.enumerated().forEach { index, _ in
                entries[index].isShown = false
            }
        }
    }
}

extension MapModel: nonisolated Comparable {
    nonisolated public static func < (lhs: MapModel, rhs: MapModel) -> Bool {
        return MainActor.assumeIsolated {
            lhs.name < rhs.name
    
        }
    }
}

extension MapModel: nonisolated ItemLinkRegistable {
    @MainActor public var linkRegisterModels: [LinkRegisterModel] {
        changedLinkRegisterModels(oldValue: .empty).0
    }

    @MainActor public func changedLinkRegisterModels(oldValue: MapModel) -> (added: [LinkRegisterModel], removed: [LinkRegisterModel]) {
        var added: [LinkRegisterModel] = []
        var removed: [LinkRegisterModel] = []
        
        let oldPinIds = Set(oldValue.mapPins.compactMap(\.photoId))
        let newPinIds = Set(mapPins.compactMap(\.photoId))
        
        if oldPinIds != newPinIds {
            let modelSource = ItemRowModel(itemId: id, typeId: .value)
            let addedPhotos = newPinIds.subtracting(oldPinIds)
            let removedPhotos = oldPinIds.subtracting(newPinIds)
            addedPhotos.forEach {
                added.append(LinkRegisterModel(name: "", source: modelSource, destination: ItemRowModel(itemId: $0, typeId: .photo)))
            }
            removedPhotos.forEach {
                removed.append(LinkRegisterModel(name: "", source: modelSource, destination: ItemRowModel(itemId: $0, typeId: .photo)))
            }
        }

        if oldValue.photoId != photoId {
            let modelSource = ItemRowModel(itemId: id, typeId: .map)
            if let photoId {
                added.append(LinkRegisterModel(name: "", source: modelSource, destination: ItemRowModel(itemId: photoId, typeId: .photo)))
            }
            if let oldPhotoId = oldValue.photoId {
                removed.append(LinkRegisterModel(name: "", source: modelSource, destination: ItemRowModel(itemId: oldPhotoId, typeId: .photo)))
            }
        }

        if oldValue.entries != entries {
            let addedEntryIds = Set(entries.map(\.id)).subtracting(Set(oldValue.entries.map(\.id)))
            let removedEntryIds = Set(oldValue.entries.map(\.id)).subtracting(Set(entries.map(\.id)))
            addedEntryIds.forEach {
                added.append(contentsOf: linkRegisterModels(entry: self[$0]))
            }
            removedEntryIds.forEach {
                removed.append(contentsOf: linkRegisterModels(entry: oldValue[$0]))
            }
            let sameEntryIds = Set(entries.map(\.id)).intersection(Set(oldValue.entries.map(\.id)))
            sameEntryIds.forEach {
                let oldEntry = oldValue[$0]
                let newEntry = self[$0]
                if oldEntry != newEntry {
                    removed.append(contentsOf: linkRegisterModels(entry: oldEntry, valueChanged: oldEntry.content != newEntry.content))
                    added.append(contentsOf: linkRegisterModels(entry: oldEntry, valueChanged: oldEntry.content != newEntry.content))
                }
            }
        }
        
        return (added, removed)
    }
    
    @MainActor func linkRegisterModels(entry: MapEntryModel, valueChanged: Bool = true) -> [LinkRegisterModel] {
        let source = ItemRowModel(itemId: id, entryId: entry.id, typeId: .map)
        var total: [LinkRegisterModel] = []
        if valueChanged {
            total += entry.links(for: entry.content).map {
                LinkRegisterModel(name: $0.name, source: source, destination: ItemRowModel(itemId: $0.itemId, entryId: $0.entryId, typeId: $0.module), markDown: $0.markDown)
            }
        }
        return total
    }
}

extension MapModel: nonisolated ItemDiffComparable {
    nonisolated public func merge(_ other: MapModel) -> MapModel {
        return MainActor.assumeIsolated {
            let mergedPhotoId = photoId_.merged(other: other.photoId_)
            let mergedMapPins = mapPins_.merged(other: other.mapPins_)
            let mergedCategory = category_.merged(other: other.category_)
            let mergedEntries: CRDTDataUpdate<[MapEntryModel]>
            if mergedCategory.wrappedValue == .folder {
                let allIds = Set(entries.map(\.id)).union(other.entries.map(\.id))
                let combined = allIds
                    .compactMap { id in entries.first { $0.id == id } ?? other.entries.first { $0.id == id } }
                    .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
                mergedEntries = CRDTDataUpdate(wrappedValue: combined)
            } else {
                mergedEntries = entries_.merged(other: other.entries_)
            }
            return MapModel(
                id: id,
                name: name_.merged(other: other.name_),
                description: description_.merged(other: other.description_),
                tags: tags_.merged(other: other.tags_),
                category: mergedCategory,
                displayState: other.displayState,
                entries: mergedEntries,
                displayConfig: displayConfig_.merged(other: other.displayConfig_),
                photoId: mergedPhotoId,
                width: mergedPhotoId.update == photoId_.update ? width : other.width,
                height: mergedPhotoId.update == photoId_.update ? height : other.height,
                mapPins: mergedMapPins,
                pinScale: pinScale,
                hexMapScale: hexMapScale_.merged(other: other.hexMapScale_),
                scale: other.scale,
                degrees: other.degrees,
                parentId: other.parentId
            )
    
        }
    }

    nonisolated public func isSame(_ other: MapModel) -> Bool {
        return MainActor.assumeIsolated {
            // Split comparison into typed chunks for faster type-checking
            let basicFieldsMatch: Bool = (
                name == other.name &&
                description == other.description &&
                tags == other.tags &&
                category == other.category
            )
            guard basicFieldsMatch else { return false }

            let configMatch: Bool = (
                entries_.update == other.entries_.update &&
                displayConfig == other.displayConfig &&
                photoId_.update == other.photoId_.update &&
                mapPins_.update == other.mapPins_.update &&
                hexMapScale == other.hexMapScale &&
                pinScale == other.pinScale &&
                parentId == other.parentId
            )
            guard configMatch else { return false }

            // Sanity checks
            guard entries.count == other.entries.count else { return false }
            let entriesMatch: Bool = entries.enumerated().allSatisfy { index, entry in
                entry == other.entries[index]
            }
            guard entriesMatch else { return false }

            guard mapPins.count == other.mapPins.count else { return false }
            let pinsMatch: Bool = mapPins.enumerated().allSatisfy { index, pin in
                pin == other.mapPins[index]
            }

            return pinsMatch
    
        }
    }
    
    public var version: Int {
        // Must be identical across processes and devices: the master sends this
        // version with a reveal reference, and a player re-requests the full map
        // payload whenever its local value differs. `hashValue` is randomly
        // seeded per launch, so it forced a full re-transfer on every reveal.
        Int(bitPattern: UInt(truncatingIfNeeded: Double(hexMapScale + pinScale).bitPattern))
    }
}

// MARK: - Review Properties

extension MapModel {
    @MainActor public var reviewProperties: [ReviewCustomProperty] {
        [
            ReviewCustomProperty(displayName: "Photo") { ReviewPropertyValue(photoId: ($0 as? MapModel)?.photoId) },
            ReviewCustomProperty(displayName: "Pins") { ReviewPropertyValue(($0 as? MapModel)?.mapPins.count ?? 0) },
            ReviewCustomProperty(displayName: "Pin Scale") { ReviewPropertyValue(($0 as? MapModel)?.pinScale ?? 1) },
            ReviewCustomProperty(displayName: "Hex Scale") { ReviewPropertyValue(($0 as? MapModel)?.hexMapScale ?? 0) },
            ReviewCustomProperty(displayName: "Rotation") { ReviewPropertyValue(($0 as? MapModel)?.degrees ?? 0) }
        ]
    }
}

extension MapModel: nonisolated ItemDuplicatable {
    nonisolated public func duplicate() -> MapModel {
        return MainActor.assumeIsolated {
            let copyName = duplicateName(from: name)
            return MapModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, entries: entries.map { $0.duplicate() }, displayConfig: displayConfig, photoId: photoId, width: width, height: height, mapPins: mapPins, pinScale: pinScale, hexMapScale: hexMapScale, scale: scale, degrees: degrees, parentId: parentId)
    
        }
    }
}

extension MapModel: nonisolated ItemReferencable {}

extension MapModel {
    static func decodeData(of data: Data?) -> MapModel? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(MapModel.self, from: data)
    }

    func encodeData() -> Data? {
        let encoder = JSONEncoder()
        return try? encoder.encode(self)
    }
}

extension MapModel: nonisolated ItemDataAccessable {
    public var fileUrl: FileUrl? {
        get { nil }
        set(newValue) {}
    }

    nonisolated public static var empty: MapModel { empty(UUID()) }
    nonisolated public static func empty(_ id: UUID) -> MapModel {
        MapModel(id: id, name: "")
    }
    nonisolated public static let typeId: NetworkModules = .map

    public func copy() -> MapModel {
        MapModel(id: id, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, entries: entries_, displayConfig: displayConfig_, photoId: photoId_, width: width, height: height, mapPins: mapPins_, pinScale: pinScale, hexMapScale: hexMapScale_, scale: scale, degrees: degrees, parentId: parentId)
    }

    public func filter(filter: String, includeEntries: Bool) -> Bool {
        guard !filter.isEmpty else { return true }
        guard !(name.localizedCaseInsensitiveContains(filter) || description.localizedCaseInsensitiveContains(filter)) else { return true }
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
        pinScale <=> model.pinScale
        hexMapScale_ <=> model.hexMapScale_
        scale <=> model.scale
        degrees <=> model.degrees
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
        case _pinScale
        case _hexMapScale_
        case _scale
        case _degrees
        case _parentId
    }

    nonisolated public final func encode(to encoder: Encoder) throws {
        nonisolated(unsafe) let encoder = encoder
        try MainActor.assumeIsolated {
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
            try container.encode(self._pinScale, forKey: MapModel.CodingKeys._pinScale)
            try container.encode(self._hexMapScale_, forKey: MapModel.CodingKeys._hexMapScale_)
            try container.encode(self._scale, forKey: MapModel.CodingKeys._scale)
            try container.encode(self._degrees, forKey: MapModel.CodingKeys._degrees)
            try container.encodeIfPresent(self._parentId, forKey: MapModel.CodingKeys._parentId)
    
        }
    }
}

extension MapModel: nonisolated Equatable, nonisolated Hashable {
    nonisolated public static func == (lhs: MapModel, rhs: MapModel) -> Bool {
        return MainActor.assumeIsolated {
            lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState
    
        }
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
