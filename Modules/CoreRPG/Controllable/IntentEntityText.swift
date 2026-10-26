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

    @MainActor
    public static func excerpt<Model: ItemDataAccessible>(of model: Model) -> String {
        guard !model.specialCategory else { return "" }
        var text = ""
        for entry in model.entries where entry.displayState != DisplayStateMask.totalHidden.rawValue {
            guard text.count < excerptLimit else { break }
            for part in [entry.name, entry.content] where !part.isEmpty {
                if !text.isEmpty { text += "\n" }
                text += part
            }
        }
        return String(text.prefix(excerptLimit))
    }
}

#endif
