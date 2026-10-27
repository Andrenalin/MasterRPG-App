// @copyright André Trettin

#if !os(tvOS)

import Foundation

/// The text of an item as Siri and Apple Intelligence see it: the names and contents of its
/// entries in order, with Markdown links reduced to their labels. The short `excerpt` goes into
/// the App Entity index, the longer `document` is what an entity exports when Siri hands it to
/// another app ("summarize this"). See CODE_AUDIT_AppIntents §4.5, CODE_AUDIT_AppIntents3 §4.1,
/// §4.3.
public enum IntentEntityText {
    /// Characters of entry text an entity carries. Each entity holds its own copy and every reindex
    /// builds all of them, so this stays small.
    public static let excerptLimit = 2000

    /// Characters an exported item carries at most, so a whole rule book does not stall the
    /// hand-off to another app.
    public static let documentLimit = 50_000

    /// Reads at most `excerptLimit` characters from the front of the entries: each part is cut to
    /// what is still free before it is appended, and the length is tracked, never recounted. A
    /// library of long texts costs O(limit) per entity, not O(text). `content` turns an entry into
    /// the text Siri should read (Character passes its calculated values). See
    /// CODE_AUDIT_AppIntents2 §7.1.
    @MainActor
    public static func excerpt<Model: ItemDataAccessible>(
        of model: Model,
        content: (Model.Entry) -> String = { $0.content }
    ) -> String {
        guard !model.specialCategory else { return "" }
        var text = BoundedText(limit: excerptLimit, separator: "\n")
        for entry in model.entries where entry.displayState != DisplayStateMask.totalHidden.rawValue {
            for part in [entry.name, content(entry)] {
                guard text.append(readable(part)) else { return text.value }
            }
        }
        return text.value
    }

    /// The name, the description and the visible entries (name, then text) of an item, separated
    /// by blank lines and cut at `documentLimit`. Empty for the app's own categories.
    @MainActor
    public static func document<Model: ItemDataAccessible>(
        of model: Model,
        content: (Model.Entry) -> String = { $0.content }
    ) -> String {
        guard !model.specialCategory else { return "" }
        var text = BoundedText(limit: documentLimit, separator: "\n\n")
        guard text.append(readable(model.name)), text.append(readable(model.description)) else { return text.value }
        for entry in model.entries where entry.displayState != DisplayStateMask.totalHidden.rawValue {
            let name = readable(entry.name)
            let body = readable(content(entry))
            let part = [name, body].filter { !$0.isEmpty }.joined(separator: "\n")
            guard text.append(part) else { return text.value }
        }
        return text.value
    }

    /// Characters of the description a subtitle shows at most.
    static let subtitleLimit = 80

    /// What tells two items with the same name apart when Siri asks "which one?": the name of the
    /// folder the item is in, else the first line of its description, else nothing.
    /// See CODE_AUDIT_AppIntents3 §4.11.
    @MainActor
    public static func subtitle<Model: ItemDataAccessible>(of model: Model, parent: (UUID) -> Model?) -> String {
        if let parentId = model.parentId, let folder = parent(parentId), !folder.name.isEmpty {
            return readable(folder.name)
        }
        let firstLine = readable(model.description).split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return String(firstLine.prefix(subtitleLimit))
    }

    /// `markdown` as text to read: every link `[label](target)` becomes its label (the app's links
    /// are `RPG://MODULE/0/<uuid>` targets that mean nothing to Siri and use up the excerpt), and
    /// bold markers are dropped.
    public static func readable(_ markdown: String) -> String {
        guard markdown.contains("](") || markdown.contains("**") || markdown.contains("__") else {
            return markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let withoutLinks = markdown.replacing(/\[([^\]]*)\]\([^)\s]*\)/) { String($0.output.1) }
        return withoutLinks
            .replacing("**", with: "")
            .replacing("__", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Text that grows part by part up to a limit; empty parts are skipped.
private struct BoundedText {
    let limit: Int
    let separator: String
    private(set) var value = ""
    private var length = 0

    init(limit: Int, separator: String) {
        self.limit = limit
        self.separator = separator
    }

    /// Appends `part` (cut to the free space) and reports whether there is room for more.
    mutating func append(_ part: String) -> Bool {
        guard !part.isEmpty else { return length < limit }
        let separatorLength = value.isEmpty ? 0 : separator.count
        let remaining = limit - length - separatorLength
        guard remaining > 0 else { return false }
        let piece = part.prefix(remaining)
        if separatorLength > 0 { value += separator }
        value += piece
        length += separatorLength + piece.count
        return length < limit
    }
}

#endif
