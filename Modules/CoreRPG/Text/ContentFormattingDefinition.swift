// @copyright André Trettin

import Foundation
import SwiftUI

struct ContentFormattingDefinition: AttributedTextFormattingDefinition {
    typealias Scope = AttributeScopes.ContentAttributes
    
    let links: Set<LinkDataModel.ID>
    let foregroundColor: Color
    let linkBackgroundColor: Color

    var body: some AttributedTextFormattingDefinition<Scope> {
        LinksHaveThemeForeground(links: links, foregroundColor: foregroundColor)
        LinksHaveThemeBackground(links: links, backgroundColor: linkBackgroundColor)
    }
}

struct NormalizeFonts: AttributedTextValueConstraint {
    typealias Scope = ContentFormattingDefinition.Scope
    typealias AttributeKey = AttributeScopes.SwiftUIAttributes.FontAttribute

    func constrain(_ container: inout Attributes) {
        guard container.paragraphFormat != .section else {
            container.font = .title
            return
        }

        guard let font = container.font, font != .default.bold() else { return }

        // Resolve the font in the default environment, because how the original font
        // looks in the editor is less important than how it looks in a generic context.
        let resolved = font.resolve(in: EnvironmentValues().fontResolutionContext)

        if resolved.isBold || resolved.isItalic {
            container.font = .default.bold()
        } else {
            container.font = nil
        }
    }
}

struct LinksHaveThemeForeground: AttributedTextValueConstraint {
    typealias Scope = ContentFormattingDefinition.Scope
    typealias AttributeKey = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute

    let links: Set<LinkDataModel.ID>
    let foregroundColor: Color

    func constrain(_ container: inout Attributes) {
        if let link = container.linkContent, links.contains(link) {
            container.foregroundColor = foregroundColor
        } else {
            container.foregroundColor = nil
        }
    }
}

struct LinksHaveThemeBackground: AttributedTextValueConstraint {
    typealias Scope = ContentFormattingDefinition.Scope
    typealias AttributeKey = AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute

    let links: Set<LinkDataModel.ID>
    let backgroundColor: Color

    func constrain(_ container: inout Attributes) {
        if let link = container.linkContent, links.contains(link) {
            container.backgroundColor = backgroundColor
        } else {
            container.backgroundColor = nil
        }
    }
}
