/ @copyright André Trettin

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
