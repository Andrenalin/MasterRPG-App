// @copyright André Trettin

import Foundation
import SwiftUI

extension AttributeScopes {
    struct LinkNameAttributes: AttributeScope {
        let adaptiveImageGlyph: AttributeScopes.SwiftUIAttributes.AdaptiveImageGlyphAttribute
    }
}

extension AttributeScopes {
    struct LinkModelAttributes: AttributeScope {
        let custom: CustomAttributes
        let font: AttributeScopes.SwiftUIAttributes.FontAttribute
        let ingredientName: LinkNameAttributes
    }
}

extension AttributeScopes {
    /// Attributes that capture all information and formatting available in the recipe editor.
    ///
    /// - Note: The recipe editor's `RecipeFormattingDefinition` uses this attribute scope.
    struct RecipeEditorAttributes: AttributeScope {
        /// All the semantic information of a recipe should be available in the
        /// `AttributedTextFormattingDefinition`.
        let model: LinkModelAttributes

        /// The foreground color of a range of text.
        ///
        /// - Note: This attribute is not serialized, but inferred based on the `model` attributes
        /// by the `RecipeFormattingDefinition`.
        let foregroundColor: AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
    }
}

extension AttributeScopes {
    struct CustomAttributes: AttributeScope {
        /// The attribute for specifying the semantic format for a recipe text paragraph.
        let paragraphFormat: ParagraphFormattingAttribute
        /// An attribute for marking text as a reference to a recipe's ingredient.
        let ingredient: LinkDataAttribute
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
struct LinkDataAttribute: CodableAttributedStringKey {
    typealias Value = LinkDataModel.ID

    static let name = "MasterRPG.LinkAttribute"

    static let inheritedByAddedText: Bool = false
    static let invalidationConditions: Set<AttributedString.AttributeInvalidationCondition>? = [.textChanged]
}

extension AttributeDynamicLookup {
    /// The subscript for pulling custom attributes into the dynamic attribute lookup.
    ///
    /// This makes them available throughout the code, using the name they have in the
    /// `AttributeScopes.CustomAttributes` scope.
    subscript<T: AttributedStringKey>(
        dynamicMember keyPath: KeyPath<AttributeScopes.CustomAttributes, T>
    ) -> T {
        self[T.self]
    }
}
