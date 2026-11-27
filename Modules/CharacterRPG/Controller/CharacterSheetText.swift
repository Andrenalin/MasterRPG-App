// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import GeneratorRPG
import PhotoRPG
import SwiftUI

/// The text the Character "Extract Information" analyzes: the character's values and its
/// portrait's description and tags, the same for the extraction screen and the batch.
///
/// A group entry (`valueId`) stands for a sub-character that holds the group's values; most real
/// sheets keep race, class and player there ("Basiswerte"). Its line alone would only be the
/// group's link label ("Basiswerte: Adalbert's Group"), so a group is written as a header line
/// followed by its own values, recursively.
enum CharacterSheetText {
    /// How deep groups inside groups are followed.
    static let maximumGroupDepth = 4

    /// `""` when the character has no visible values, so the batch skips it like other modules.
    /// - Parameter resolve: looks up the sub-character of a group entry.
    @MainActor static func text(
        for model: ValueModel,
        photoRoot: PhotoRootModel?,
        resolve: (UUID) -> ValueModel?
    ) -> String {
        var visited: Set<UUID> = [model.id]
        let entries = sheetEntries(of: model, resolve: resolve, depth: 0, visited: &visited)
        guard !entries.isEmpty else { return "" }
        let portrait = portrait(of: model, photoRoot: photoRoot)
        return TextSummaryExtractionFormatter.formatCharacter(
            title: String(localized: "Character", bundle: .module),
            name: model.name,
            entries: entries,
            portraitDescription: portrait.description,
            portraitTags: portrait.tags
        )
    }

    /// The visible values; a group is its name (no content) followed by its sub-character's
    /// values. A group that is not found, too deep or already written keeps only its name.
    @MainActor static func sheetEntries(
        of model: ValueModel,
        resolve: (UUID) -> ValueModel?,
        depth: Int,
        visited: inout Set<UUID>
    ) -> [(name: String, content: String)] {
        var result: [(name: String, content: String)] = []
        for entry in model.entries where !entry.isGroupHidden {
            guard let groupId = entry.valueId else {
                result.append((entry.name, entry.value))
                continue
            }
            result.append((entry.name, ""))
            guard depth < maximumGroupDepth, visited.insert(groupId).inserted, let group = resolve(groupId) else {
                continue
            }
            result.append(contentsOf: sheetEntries(of: group, resolve: resolve, depth: depth + 1, visited: &visited))
        }
        return result
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
