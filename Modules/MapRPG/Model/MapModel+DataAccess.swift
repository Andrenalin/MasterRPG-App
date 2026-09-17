// @copyright André Trettin

import CoreRPG
import Foundation

// Split out of MapModel.swift — see CODE_AUDIT §9.13.

// MARK: - Review Properties

extension MapModel {
    @MainActor public var reviewProperties: [ReviewCustomProperty] {
        [
            ReviewCustomProperty(displayName: String(localized: "Photo", bundle: .module)) { ReviewPropertyValue(photoId: ($0 as? MapModel)?.photoId) },
            ReviewCustomProperty(displayName: String(localized: "Pins", bundle: .module)) { ReviewPropertyValue(($0 as? MapModel)?.mapPins.count ?? 0) },
            ReviewCustomProperty(displayName: String(localized: "Walls", bundle: .module)) { ReviewPropertyValue(($0 as? MapModel)?.walls.count ?? 0) },
            ReviewCustomProperty(displayName: String(localized: "Pin Scale", bundle: .module)) { ReviewPropertyValue(($0 as? MapModel)?.pinScale ?? 1) },
            ReviewCustomProperty(displayName: String(localized: "Hex Scale", bundle: .module)) { ReviewPropertyValue(($0 as? MapModel)?.hexMapScale ?? 0) },
            ReviewCustomProperty(displayName: String(localized: "Rotation", bundle: .module)) { ReviewPropertyValue(($0 as? MapModel)?.degrees ?? 0) }
        ]
    }
}

extension MapModel: nonisolated ItemDuplicatable {
    nonisolated public func duplicate() -> MapModel {
        return assumeMainActorIsolated {
            let copyName = duplicateName(from: name)
            return MapModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, entries: entries.map { $0.duplicate() }, displayConfig: displayConfig, photoId: photoId, width: width, height: height, mapPins: mapPins, walls: walls, pinScale: pinScale, hexMapScale: hexMapScale, scale: scale, degrees: degrees, parentId: parentId)

        }
    }
}

extension MapModel: nonisolated ItemReferencable {}

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
        MapModel(id: id, name: name_, description: description_, tags: tags_, category: category_, displayState: displayState, entries: entries_, displayConfig: displayConfig_, photoId: photoId_, width: width, height: height, mapPins: mapPins_, walls: walls_, pinScale: pinScale, hexMapScale: hexMapScale_, scale: scale, degrees: degrees, parentId: parentId)
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
