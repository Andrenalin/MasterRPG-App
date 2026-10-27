// @copyright André Trettin

#if !os(tvOS)

import Foundation

/// The searchable body text of an item for its App Entity: the names and contents of its entries,
/// cut off at a bounded length. Spotlight and Siri can then match words from the story, the rules
/// or the notes of an item, not only its name and summary. See CODE_AUDIT_AppIntents §4.5.
public enum IntentEntityText {
    /// Characters of entry text an entity carries. Each entity holds its own copy and every reindex
    /// builds all of them, so this stays small.
    public static let excerptLimit = 2000

    /// Reads at most `excerptLimit` characters from the front of the entries: each part is cut to
    /// what is still free before it is appended, and the length is tracked, never recounted. A
    /// library of long texts costs O(limit) per entity, not O(text). See CODE_AUDIT_AppIntents2 §7.1.
    @MainActor
    public static func excerpt<Model: ItemDataAccessible>(of model: Model) -> String {
        guard !model.specialCategory else { return "" }
        var text = ""
        var length = 0
        for entry in model.entries where entry.displayState != DisplayStateMask.totalHidden.rawValue {
            for part in [entry.name, entry.content] where !part.isEmpty {
                let separator = text.isEmpty ? 0 : 1
                let remaining = excerptLimit - length - separator
                guard remaining > 0 else { return text }
                let piece = part.prefix(remaining)
                if separator == 1 { text += "\n" }
                text += piece
                length += separator + piece.count
            }
        }
        return text
    }
}

#endif
