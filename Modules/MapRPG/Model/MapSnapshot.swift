// @copyright André Trettin

import CoreRPG
import Foundation
import CoreGraphics

/// Sendable value snapshot of a MapModel — the only representation that crosses
/// the Core Data context boundary. Not Codable: the .gmz wire format stays on
/// MapModel's Codable implementation.
struct MapSnapshot: Sendable, Identifiable {
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
}
