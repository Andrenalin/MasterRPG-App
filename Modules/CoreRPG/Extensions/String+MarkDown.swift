// @copyright André Trettin

import Foundation

public extension String {
    func markDown(asBold: Bool = false) -> AttributedString {
        var bold = ""
        if asBold && !starts(with: "**") {
            bold = "**"
        }
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text = try? AttributedString(markdown: "\(bold)\(trimmed)\(bold)", options: .init(allowsExtendedAttributes: true, interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return AttributedString(self)
        }
        return text
    }

    func markDownText(asBold: Bool = false) -> String {
        var bold = ""
        if asBold && !starts(with: "**") {
            bold = "**"
        }
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(bold)\(trimmed)\(bold)"
    }


    /// The text without backticks and with every markdown link reduced to its label, through the
    /// shared `LinkBuilder.markdownLinkPattern`. See CODE_AUDIT_Since_3.0.1 §9.3.
    func withoutLink() -> String {
        LinkBuilder.labels(in: replacing("`", with: ""))
    }

    /// The text with each range replaced by its text, in order of position. A range that overlaps
    /// one before it is skipped. The ranges must be ranges of this string.
    /// See CODE_AUDIT_Since_3.0.1 §9.3.
    func replacing(ranges replacements: [(range: Range<String.Index>, text: String)]) -> String {
        var result = ""
        var position = startIndex
        for replacement in replacements.sorted(by: { $0.range.lowerBound < $1.range.lowerBound })
        where replacement.range.lowerBound >= position {
            result += self[position..<replacement.range.lowerBound]
            result += replacement.text
            position = replacement.range.upperBound
        }
        result += self[position...]
        return result
    }
}
