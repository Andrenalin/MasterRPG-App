// @copyright André Trettin

import CoreRPG
import Foundation
import CoreGraphics

/// Sendable value snapshot of a MapModel — the only representation that crosses
/// isolation boundaries. The normal `.gmz` wire format stays on `MapModel`;
/// Codable conformance here is used by the photo-free live map update payload.
struct MapSnapshot: Codable, Sendable, Identifiable {
    let id: UUID
    let name: CRDT<String>
    let description: CRDT<String>
    let tags: CRDT<[String]>
    let category: CRDT<ItemListCategory>
    let displayState: Int
    let entries: CRDTDataUpdate<[MapEntryModel]>
    let displayConfig: CRDTDataUpdate<DisplayConfigModel>
    let photoId: CRDTDataUpdate<UUID?>
    let width: CGFloat
    let height: CGFloat
    let mapPins: CRDTDataUpdate<[MapPinModel]>
    let walls: CRDTDataUpdate<[MapWallModel]>
    let pinScale: CGFloat
    let hexMapScale: CRDT<Double>
    let scale: CGFloat
    let degrees: Double
    let parentId: UUID?
}

extension MapSnapshot {
    @MainActor
    init(_ model: MapModel) {
        id = model.id
        name = model.name_
        description = model.description_
        tags = model.tags_
        category = model.category_
        displayState = model.displayState
        entries = model.entries_
        displayConfig = model.displayConfig_
        photoId = model.photoId_
        width = model.width
        height = model.height
        mapPins = model.mapPins_
        walls = model.walls_
        pinScale = model.pinScale
        hexMapScale = model.hexMapScale_
        scale = model.scale
        degrees = model.degrees
        parentId = model.parentId
    }

    @MainActor
    func makeModel() -> MapModel {
        MapModel(
            id: id,
            name: name,
            description: description,
            tags: tags,
            category: category,
            displayState: displayState,
            entries: entries,
            displayConfig: displayConfig,
            photoId: photoId,
            width: width,
            height: height,
            mapPins: mapPins,
            walls: walls,
            pinScale: pinScale,
            hexMapScale: hexMapScale,
            scale: scale,
            degrees: degrees,
            parentId: parentId
        )
    }

    /// Applies authoritative map metadata without replacing the observed model.
    /// Runtime-only presentation state belongs to `mapState`, so it survives a
    /// structural map update that happens to arrive later.
    @MainActor
    func apply(to model: MapModel) {
        let pointer = model.pointer
        let entryRuntimeState = Dictionary(
            uniqueKeysWithValues: model.entries.map { ($0.id, (isShown: $0.isShown, focused: $0.focused)) }
        )
        let localPins = Dictionary(uniqueKeysWithValues: model.mapPins.map { ($0.id, $0) })

        var updatedEntries = entries.wrappedValue
        for index in updatedEntries.indices {
            guard let runtimeState = entryRuntimeState[updatedEntries[index].id] else { continue }
            updatedEntries[index].isShown = runtimeState.isShown
            updatedEntries[index].focused = runtimeState.focused
        }

        let updatedPins = mapPins.wrappedValue.map { incomingPin in
            guard let localPin = localPins[incomingPin.id],
                  localPin.timeInterval > incomingPin.timeInterval else {
                return incomingPin
            }
            // The timestamp sequences live map state, not editor metadata. Keep
            // every newer live field while name/photo/color/ownership from this
            // structural update remain authoritative.
            var updatedPin = incomingPin
            updatedPin.location = localPin.location
            updatedPin.isShown = localPin.isShown
            updatedPin.size = localPin.size
            updatedPin.isZoom = localPin.isZoom
            updatedPin.isDead = localPin.isDead
            updatedPin.isHighlighted = localPin.isHighlighted
            updatedPin.timeInterval = localPin.timeInterval
            return updatedPin
        }
        model.name_ = name
        model.description_ = description
        model.tags_ = tags
        model.category_ = category
        model.displayState = displayState
        model.entries_ = entries
        model.entries = updatedEntries
        model.displayConfig_ = displayConfig
        model.photoId_ = photoId
        model.width = width
        model.height = height
        model.mapPins_ = mapPins
        model.mapPins = updatedPins
        model.walls_ = walls
        model.pinScale = pinScale
        model.hexMapScale_ = hexMapScale
        model.scale = scale
        model.degrees = degrees
        model.parentId = parentId
        model.pointer = pointer
    }
}

// Keep live-map payloads produced before wall support readable. All other fields retain their
// established required-key behavior; only the additive wall field defaults when absent.
extension MapSnapshot {
    private enum CodingKeys: CodingKey {
        case id
        case name
        case description
        case tags
        case category
        case displayState
        case entries
        case displayConfig
        case photoId
        case width
        case height
        case mapPins
        case walls
        case pinScale
        case hexMapScale
        case scale
        case degrees
        case parentId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(CRDT<String>.self, forKey: .name)
        description = try container.decode(CRDT<String>.self, forKey: .description)
        tags = try container.decode(CRDT<[String]>.self, forKey: .tags)
        category = try container.decode(CRDT<ItemListCategory>.self, forKey: .category)
        displayState = try container.decode(Int.self, forKey: .displayState)
        entries = try container.decode(CRDTDataUpdate<[MapEntryModel]>.self, forKey: .entries)
        displayConfig = try container.decode(CRDTDataUpdate<DisplayConfigModel>.self, forKey: .displayConfig)
        photoId = try container.decode(CRDTDataUpdate<UUID?>.self, forKey: .photoId)
        width = try container.decode(CGFloat.self, forKey: .width)
        height = try container.decode(CGFloat.self, forKey: .height)
        mapPins = try container.decode(CRDTDataUpdate<[MapPinModel]>.self, forKey: .mapPins)
        walls = try container.decodeIfPresent(CRDTDataUpdate<[MapWallModel]>.self, forKey: .walls) ?? CRDTDataUpdate(wrappedValue: [])
        pinScale = try container.decode(CGFloat.self, forKey: .pinScale)
        hexMapScale = try container.decode(CRDT<Double>.self, forKey: .hexMapScale)
        scale = try container.decode(CGFloat.self, forKey: .scale)
        degrees = try container.decode(Double.self, forKey: .degrees)
        parentId = try container.decodeIfPresent(UUID.self, forKey: .parentId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(tags, forKey: .tags)
        try container.encode(category, forKey: .category)
        try container.encode(displayState, forKey: .displayState)
        try container.encode(entries, forKey: .entries)
        try container.encode(displayConfig, forKey: .displayConfig)
        try container.encode(photoId, forKey: .photoId)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(mapPins, forKey: .mapPins)
        try container.encode(walls, forKey: .walls)
        try container.encode(pinScale, forKey: .pinScale)
        try container.encode(hexMapScale, forKey: .hexMapScale)
        try container.encode(scale, forKey: .scale)
        try container.encode(degrees, forKey: .degrees)
        try container.encodeIfPresent(parentId, forKey: .parentId)
    }
}
