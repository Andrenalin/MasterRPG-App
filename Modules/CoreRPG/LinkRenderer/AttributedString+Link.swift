// @copyright André Trettin

import Foundation
import SwiftUI

extension AttributedString {
    public func toggleLink(url: String, with insertedText: String, replace: Bool = false) -> AttributedString {
        var foundLink = false
        var foundLinkRange: Range<AttributedString.Index>? = nil
        var foundExpanded = false
        var expandedStartRange: Range<AttributedString.Index>? = nil
        var expandedEndRange: Range<AttributedString.Index>? = nil
        var openLinks = 0
        var level = 0

        let searchUrl = (url.split(separator: "]").last ?? Substring(url)).trimmingCharacters(in: CharacterSet(charactersIn: "()"))

        for run in runs {
            
            if let hasLink = run[AttributeScopes.FoundationAttributes.LinkAttribute.self] {
                if !foundLink && hasLink.absoluteString.contains(searchUrl) {
                    foundLink = true
                    foundLinkRange = run.range
                    level = openLinks
                }
                continue
            }
            if run.description.starts(with: " ➡️ ") {
                openLinks += 1
                if !foundExpanded && foundLink {
                    foundExpanded = true
                    expandedStartRange = run.range
                }
            }
            if run.description.contains("⬅️") {
                openLinks -= 1
                if foundLink && foundExpanded && openLinks <= level {
                    expandedEndRange = run.range
                    break
                }
            }
            if foundLink && openLinks == 0 {
                break
            }
        }

        guard let foundLinkRange else { return self }

        if foundExpanded {
            var result = self
            if let expandedStartRange {
                if let expandedEndRange {
                    let endIndex = result.index(beforeCharacter: expandedEndRange.upperBound)
                    let expandedRange = expandedStartRange.lowerBound ... endIndex
                    result.removeSubrange(expandedRange)
                } else {
                    let expandedRange = expandedStartRange.lowerBound...
                    result.removeSubrange(expandedRange)
                }
            }
            if replace {
                result.replaceSubrange(foundLinkRange, with: AttributedString(stringLiteral: insertedText))
            }
            return result
        } else {
            // case not expanded
            var mergedText = insertedText
            mergedText.insert(contentsOf: " ➡️ ", at: mergedText.startIndex)
            mergedText.insert(contentsOf: " ⬅️ ", at: mergedText.endIndex)

            var attributed = (try? AttributedString(markdown: mergedText, options: .init(allowsExtendedAttributes: true, interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(mergedText)
            attributed.mergeAttributes(AttributedString.blockAttributes(for: level + 1))

            var result = self
            result.insert(attributed, at: foundLinkRange.upperBound)
            return result
        }
    }

    static func blockAttributes(for level: Int) -> AttributeContainer {
        var attributes = AttributeContainer()
        if level == 0 {
            return attributes
        }
        let color: Color
        if level % 2 == 1 {
            color = .indigo
        } else {
            color = .indigo.opacity(0.8)
        }
        
        attributes[AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] = color
        return attributes
    }
}
