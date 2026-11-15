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
    var hasRecordedDegrees: Bool = true
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
        hasRecordedDegrees = model.hasRecordedDegrees
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
            parentId: parentId,
            hasRecordedDegrees: hasRecordedDegrees
        )
    }

    /// Applies authoritative map metadata without replacing the observed model.
    /// Runtime-only presentation state belongs to `mapState`, so it survives a
    /// structural map update that happens to arrive later.
    @MainActor
    func apply(to model: MapModel) {
        let pointer = model.pointer
        // uniquingKeysWith (last-wins) rather than uniqueKeysWithValues, which
        // traps on a duplicate id — this model can be built from a decoded
        // network payload. See CODE_AUDIT_Game §5.5.
        let entryRuntimeState = Dictionary(
            model.entries.map { ($0.id, (isShown: $0.isShown, focused: $0.focused)) },
            uniquingKeysWith: { _, new in new }
        )
        let localPins = Dictionary(model.mapPins.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })

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
            updatedPin.isPhotoShared = localPin.isPhotoShared
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
        model.hasRecordedDegrees = hasRecordedDegrees
        model.parentId = parentId
        model.pointer = pointer
    }
}

extension MapSnapshot {
    /// Strips GM-only content before this snapshot crosses the wire to a
    /// non-master peer: the description and tags, the name and text of hidden rooms, and every hidden pin (a shown monster
    /// inside a hidden room counts as hidden). A hidden pin is
    /// left out entirely (as in the live `mapState`), so its name, portrait, character link,
    /// position and even its existence stay on the master until it is shown. Client-side
    /// `isShown` checks only ever suppressed *rendering* — the underlying data was otherwise
    /// fully present on every recipient's device the moment a map package or content update
    /// arrived, defeating fog-of-war. See CODE_AUDIT §6.1, CODE_AUDIT_22a §6.2.
    ///
    /// Invariant: blanking a hidden room's `name` and `content` goes through the `@CRDT` setters, so
    /// the blank text carries a fresh timestamp and would win a CRDT merge against the master's
    /// older real text. It is only safe because the receive paths for a map package and for a
    /// reveal import with `ImportMode.overwrite` (not a merge), which replaces the blank text.
    /// Do not send a redacted snapshot through a merging path. See CODE_AUDIT_26 §5.95.
    func redactedForNonMaster() -> MapSnapshot {
        let redactedEntries = entries.wrappedValue.map { entry -> MapEntryModel in
            var redacted = entry
            guard !redacted.isShown else { return redacted }
            redacted.name = ""
            redacted.content = ""
            return redacted
        }
        let redactedPins = mapPins.wrappedValue.filter { $0.isVisibleToPlayers(hiddenBy: entries.wrappedValue) }
        // The description is the game master's notes field (spoilers, hints about secret rooms)
        // and the tags are their own filing; neither is shown to players, so neither is sent.
        // The name stays. See CODE_AUDIT_26 §6.7.
        var redactedDescription = description
        redactedDescription.wrappedValue = ""
        var redactedTags = tags
        redactedTags.wrappedValue = []
        return MapSnapshot(
            id: id,
            name: name,
            description: redactedDescription,
            tags: redactedTags,
            category: category,
            displayState: displayState,
            entries: CRDTDataUpdate(wrappedValue: redactedEntries, update: entries.$update),
            displayConfig: displayConfig,
            photoId: photoId,
            width: width,
            height: height,
            mapPins: CRDTDataUpdate(wrappedValue: redactedPins, update: mapPins.$update),
            walls: CRDTDataUpdate(wrappedValue: walls.wrappedValue.map { $0.redactedForPlayers() }, update: walls.$update),
            pinScale: pinScale,
            hexMapScale: hexMapScale,
            scale: scale,
            degrees: degrees,
            parentId: parentId,
            hasRecordedDegrees: hasRecordedDegrees
        )
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
        case hasRecordedDegrees
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
        // A sender that predates the flag never stored its rotation, so its `degrees` is not a record.
        hasRecordedDegrees = try container.decodeIfPresent(Bool.self, forKey: .hasRecordedDegrees) ?? false
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
        try container.encode(hasRecordedDegrees, forKey: .hasRecordedDegrees)
    }
}
