// @copyright André Trettin

import Foundation

/// The one definition of what a generated tag is. PDF, photo and table analysis build their
/// `@Guide` text and their instructions from it, and the tag evaluation in the tests reads the same
/// numbers and words, so the prompts and the rules that judge them cannot drift apart.
enum GeneratedTagRules {
    /// How many tags an analysis returns. The tag UI cannot show more than the upper bound.
    static let countRange = 3...5

    /// Tags are short keywords of one to three words.
    static let maximumWordsPerTag = 3

    /// Words that must not appear in a tag. They fit every RPG document, so a tag with them wastes
    /// one of the few slots. Table analysis keeps them out of its description too.
    static let bannedWords = ["RPG", "Setting", "Mechanics", "Use Case"]

    /// Generic labels every kind of item can have. Kinds add their own, e.g. "Image" for photos.
    static let genericTags = ["System", "Genre"]

    /// "3 to 5"
    static var countText: String {
        "\(countRange.lowerBound) to \(countRange.upperBound)"
    }

    /// `"RPG", "Setting", "Mechanics" or "Use Case"`
    static var bannedWordsText: String {
        quotedList(bannedWords)
    }

    /// The format rules every tag list follows, for the instructions of the model.
    /// - Parameter extraGenericTags: generic words of one kind of item, for example "Image".
    static func rules(extraGenericTags: [String] = []) -> String {
        """
        Write every tag in the output language, translate the kind of tag too. A tag has 1 to \
        \(maximumWordsPerTag) words. Never use a colon in a tag and never write a label before a \
        value ("Genre: Fantasy", "Ausrüstung: Handel"), write only the value ("Fantasy", "Handel"). Never repeat the title as a tag and never repeat a tag. Never \
        use the words \(bannedWordsText) in a tag, and never use generic tags such as \
        \(quotedList(genericTags + extraGenericTags)) (or their translations).
        """
    }

    /// The `@Guide` text of a `tags` property: the count, what each tag says, and the format rules.
    /// - Parameter contents: which tag says what, specific to the kind of item.
    static func guideDescription(contents: String, extraGenericTags: [String] = []) -> String {
        "\(countText) short tags. \(contents) \(rules(extraGenericTags: extraGenericTags))"
    }

    /// The tags as they are stored: a `Label: value` tag is cut to its value ("Gueter: Lebensmittel"
    /// becomes "Lebensmittel"), empty and repeated tags go, and no more than `countRange.upperBound`
    /// remain. The prompts forbid labels, but the on-device model still writes them now and then,
    /// and the tag UI cannot show a label in front of every tag.
    static func cleaned(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let value = withoutLabel(tag)
            let key = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            if !value.isEmpty, seen.insert(key).inserted {
                result.append(value)
            }
        }
        return Array(result.prefix(countRange.upperBound))
    }

    /// The part after the last colon; the part before it when nothing follows the colon.
    static func withoutLabel(_ tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.lastIndex(of: ":") else {
            return trimmed
        }
        let value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? trimmed[..<colon].trimmingCharacters(in: .whitespacesAndNewlines) : value
    }

    private static func quotedList(_ words: [String]) -> String {
        let quoted = words.map { "\"\($0)\"" }
        guard let last = quoted.last, quoted.count > 1 else {
            return quoted.first ?? ""
        }
        return quoted.dropLast().joined(separator: ", ") + " or " + last
    }
}
