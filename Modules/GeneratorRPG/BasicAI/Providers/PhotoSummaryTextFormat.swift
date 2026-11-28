// @copyright André Trettin

import Foundation

/// The plain-text answer format of the on-device photo analysis.
///
/// The on-device guardrails block many ordinary RPG portraits (an old pirate with a sabre, a
/// bearded man with glasses) whatever the prompt says, see `PhotoGuardrailProbeTests`. Only
/// `.permissiveContentTransformations` lets them through, and that mode applies to `String`
/// responses only, not to guided generation. So the model answers in three labelled lines and this
/// type reads them back into a `PhotoSummaryAnalysis`.
enum PhotoSummaryTextFormat {

    /// The answer layout the prompt asks for.
    static let layout = """
    Title: <a title of 2 to 5 words that names the main subject>
    Description: <what is visible, in 2 to 3 sentences>
    Tags: <\(GeneratedTagRules.countText) tags, separated by commas>
    """

    private enum Field {
        case title, summary, tags
    }

    /// Labels the model writes, in English as asked, or translated into the output language.
    private static let labels: [(label: String, field: Field)] = [
        ("title", .title), ("titel", .title), ("titre", .title), ("título", .title), ("titolo", .title),
        ("description", .summary), ("beschreibung", .summary), ("descripción", .summary), ("descrizione", .summary),
        ("tags", .tags), ("schlagwörter", .tags), ("schlagworte", .tags), ("stichwörter", .tags),
        ("étiquettes", .tags), ("etiquetas", .tags), ("keywords", .tags)
    ]

    /// The analysis in `text`, or `nil` when the description or the tags are missing, which is
    /// how a refusal ("Sorry, I can't help with that.") reads.
    static func analysis(from text: String) -> PhotoSummaryAnalysis? {
        var values: [Field: String] = [:]
        var current: Field?
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = cleanedLine(String(rawLine))
            guard !line.isEmpty else {
                continue
            }
            if let (field, value) = labelled(line) {
                current = field
                values[field] = value
            } else if let field = current, field != .tags {
                // A description the model wrapped over several lines.
                values[field] = [values[field], line].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            }
        }
        let summary = values[.summary]?.trimmingCharacters(in: .whitespaces) ?? ""
        let tags = values[.tags].map(splitTags) ?? []
        guard !summary.isEmpty, !tags.isEmpty else {
            return nil
        }
        return PhotoSummaryAnalysis(
            title: values[.title].map(unquoted) ?? "",
            summary: summary,
            tags: tags
        )
    }

    // MARK: - Private

    /// Without markdown bold, list bullets and surrounding spaces.
    private static func cleanedLine(_ line: String) -> String {
        var result = line.replacing("**", with: "").trimmingCharacters(in: .whitespaces)
        while let first = result.first, "-*•#".contains(first) {
            result = String(result.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    private static func labelled(_ line: String) -> (Field, String)? {
        guard let colon = line.firstIndex(of: ":") else {
            return nil
        }
        let label = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        guard let field = labels.first(where: { $0.label == label })?.field else {
            return nil
        }
        return (field, String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
    }

    private static func splitTags(_ value: String) -> [String] {
        value.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { unquoted(String($0)).trimmingCharacters(in: CharacterSet(charactersIn: ".#")) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func unquoted(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”„'«»"))
            .trimmingCharacters(in: .whitespaces)
    }
}
