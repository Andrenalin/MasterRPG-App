// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import GeneratorRPG
import PhotoRPG
import SwiftUI

/// The text the Map "Extract Information" analyzes: the map's rooms and its photo's description
/// and tags, the same for the extraction screen and the batch.
enum MapSheetText {
    /// The rooms the analysis reads: not the hex grid, not hidden entries.
    @MainActor static func rooms(of model: MapModel) -> [MapEntryModel] {
        model.entries.filter { !$0.isHexGrid && !$0.isGroupHidden }
    }

    /// `""` when the map has no rooms, so the batch skips it like other modules.
    @MainActor static func text(for model: MapModel, photoRoot: PhotoRootModel?) -> String {
        let rooms = rooms(of: model)
        guard !rooms.isEmpty else { return "" }
        let photo = photo(of: model, photoRoot: photoRoot)
        return TextSummaryExtractionFormatter.formatMap(
            title: String(localized: "Map", bundle: .module),
            name: model.name,
            entries: rooms.map { ($0.name, $0.content) },
            photoDescription: photo.description,
            photoTags: photo.tags
        )
    }

    /// Whether the map photo adds anything to the analysis. `false` without a photo, or when its
    /// description and tags are both empty; the extraction screen then asks for them.
    @MainActor static func hasPhotoText(for model: MapModel, photoRoot: PhotoRootModel?) -> Bool {
        let photo = photo(of: model, photoRoot: photoRoot)
        return !photo.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || photo.tags.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    @MainActor private static func photo(of model: MapModel, photoRoot: PhotoRootModel?) -> (description: String, tags: [String]) {
        guard let photo = model.photoId.flatMap({ photoRoot?.itemControllable.itemSync(for: $0) }) else {
            return ("", [])
        }
        return (photo.description, photo.tags)
    }
}

#endif
