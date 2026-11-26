// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import GeneratorRPG
import PhotoRPG
import SwiftUI

/// The text the Character "Extract Information" analyzes: the character's values and its
/// portrait's description and tags, the same for the extraction screen and the batch.
enum CharacterSheetText {
    /// `""` when the character has no visible values, so the batch skips it like other modules.
    @MainActor static func text(for model: ValueModel, photoRoot: PhotoRootModel?) -> String {
        let entries = model.entries.filter { !$0.isGroupHidden }
        guard !entries.isEmpty else { return "" }
        let portrait = portrait(of: model, photoRoot: photoRoot)
        return TextSummaryExtractionFormatter.formatCharacter(
            title: String(localized: "Character", bundle: .module),
            name: model.name,
            entries: entries.map { ($0.name, $0.content) },
            portraitDescription: portrait.description,
            portraitTags: portrait.tags
        )
    }

    /// Whether the portrait adds anything to the analysis. `false` without a portrait, or when
    /// its description and tags are both empty; the extraction screen then asks for them.
    @MainActor static func hasPortraitText(for model: ValueModel, photoRoot: PhotoRootModel?) -> Bool {
        let portrait = portrait(of: model, photoRoot: photoRoot)
        return !portrait.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || portrait.tags.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    @MainActor private static func portrait(of model: ValueModel, photoRoot: PhotoRootModel?) -> (description: String, tags: [String]) {
        guard let photo = model.photoId.flatMap({ photoRoot?.itemControllable.itemSync(for: $0) }) else {
            return ("", [])
        }
        return (photo.description, photo.tags)
    }
}

#endif
