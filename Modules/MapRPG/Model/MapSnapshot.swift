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

        var updatedPins = mapPins.wrappedValue.map { incomingPin in
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
        let incomingPinIds = Set(updatedPins.map(\.id))
        // Player pins are game-session state and may have been created after the
        // sender captured its structural snapshot.
        updatedPins.append(contentsOf: localPins.values.filter {
            $0.isPlayer && !incomingPinIds.contains($0.id)
        })

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
        model.pinScale = pinScale
        model.hexMapScale_ = hexMapScale
        model.scale = scale
        model.degrees = degrees
        model.parentId = parentId
        model.pointer = pointer
    }
}
