// @copyright André Trettin

import Foundation
import SwiftUI

extension AttributeScopes {
    struct ContentAttributes: AttributeScope {
        let custom: CustomAttributes
        let font: AttributeScopes.SwiftUIAttributes.FontAttribute
        let underlineStyle: AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute
        let adaptiveImageGlyph: AttributeScopes.SwiftUIAttributes.AdaptiveImageGlyphAttribute
        let alignment: AttributeScopes.CoreTextAttributes.TextAlignmentAttribute
        let lineHeight: AttributeScopes.CoreTextAttributes.LineHeightAttribute

        let linkName: LinkNameAttributes
    }

    struct LinkNameAttributes: AttributeScope {
        let foregroundColor: AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
        let backgroundColor: AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute
    }
    
    struct CustomAttributes: AttributeScope {
        let paragraphFormat: ParagraphFormattingAttribute
        let linkContent: LinkContentAttribute
    }

}

/// The semantic format of a text paragraph.
enum ParagraphFormat: Codable {
    /// Regular text.
    case body
    /// A section header.
    case section
}

/// An attribute for specifying the semantic format for a recipe text paragraph.
struct ParagraphFormattingAttribute: CodableAttributedStringKey {
    typealias Value = ParagraphFormat

    static let name = "MasterRPG.ParagraphFormattingAttribute"

    static let runBoundaries: AttributedString.AttributeRunBoundaries? = .paragraph
    static let inheritedByAddedText: Bool = false
}

/// An attribute for marking text as a reference to a recipe's ingredient.
struct LinkContentAttribute: CodableAttributedStringKey, TextAttribute {
    typealias Value = LinkDataModel.ID

    static let name = "MasterRPG.LinkContentAttribute"
    static let inheritedByAddedText: Bool = false
}

extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(
        dynamicMember keyPath: KeyPath<AttributeScopes.CustomAttributes, T>
    ) -> T {
        self[T.self]
    }
}
