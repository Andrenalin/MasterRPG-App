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

