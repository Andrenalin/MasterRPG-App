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


    func withoutLink() -> String {
        var result = self
        result = result.replacing("`", with: "")
        var searchRange = Range(uncheckedBounds: (result.startIndex, result.endIndex))
        while let range = result.range(of: "](", range: searchRange),
                let closing = result.range(of: ")", range: Range(uncheckedBounds: (range.upperBound, result.endIndex))) {
            
            if let opening = result.range(of: "[", options: .backwards, range: Range(uncheckedBounds: (result.startIndex, range.lowerBound))) {

                let urlRange = Range(uncheckedBounds: (range.lowerBound, closing.upperBound))
                result.replaceSubrange(urlRange, with: "")
                
                let openingRange = Range(uncheckedBounds: (opening.lowerBound, opening.upperBound))
                result.replaceSubrange(openingRange, with: "")
                
                searchRange = Range(uncheckedBounds: (result.startIndex, result.endIndex))
            } else {
                searchRange = Range(uncheckedBounds: (range.upperBound, result.endIndex))
            }
        }
        return result
    }
}
