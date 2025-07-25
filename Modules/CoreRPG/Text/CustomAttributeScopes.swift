// @copyright André Trettin

import Foundation
import SwiftUI

struct ContentFormattingDefinition: AttributedTextFormattingDefinition {
    struct Scope: AttributeScope {
        let font: AttributeScopes.SwiftUIAttributes.FontAttribute
        let foregroundColor: AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
        let backgroundColor: AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute
        let underlineStyle: AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute
        let adaptiveImageGlyph: AttributeScopes.SwiftUIAttributes.AdaptiveImageGlyphAttribute
        public let alignment: AttributeScopes.CoreTextAttributes.TextAlignmentAttribute
        public let lineHeight: AttributeScopes.CoreTextAttributes.LineHeightAttribute

        let linkName: AttributeScopes.LinkNameAttributes
    }


    var body: some AttributedTextFormattingDefinition<Scope> {
        IngredientsAreGreen()
    }
}

struct IngredientsAreGreen: AttributedTextValueConstraint {
    typealias Scope = ContentFormattingDefinition.Scope
    typealias AttributeKey = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute

    func constrain(_ container: inout Attributes) {
        if container.ingredient != nil {
            container.foregroundColor = .green
        } else {
            container.foregroundColor = nil
        }
    }
}

extension AttributeScopes {
    struct ContentAttributes: AttributeScope {
        let custom: CustomAttributes
        let font: AttributeScopes.SwiftUIAttributes.FontAttribute
        let underlineStyle: AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute
        let adaptiveImageGlyph: AttributeScopes.SwiftUIAttributes.AdaptiveImageGlyphAttribute
        public let alignment: AttributeScopes.CoreTextAttributes.TextAlignmentAttribute
        public let lineHeight: AttributeScopes.CoreTextAttributes.LineHeightAttribute

        let ingredientName: LinkNameAttributes
    }

    struct LinkNameAttributes: AttributeScope {
        let foregroundColor: AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
        let backgroundColor: AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute
    }
    
    struct CustomAttributes: AttributeScope {
        let paragraphFormat: ParagraphFormattingAttribute
        let ingredient: LinkContentAttribute
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
struct LinkContentAttribute: CodableAttributedStringKey {
    typealias Value = LinkDataModel.ID

    static let name = "MasterRPG.IngredientAttribute"
}

extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(
        dynamicMember keyPath: KeyPath<AttributeScopes.CustomAttributes, T>
    ) -> T {
        self[T.self]
    }
}
