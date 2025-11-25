// @copyright André Trettin

import Foundation
import SwiftUI

struct ContentFormattingDefinition: AttributedTextFormattingDefinition {
    typealias Scope = AttributeScopes.ContentAttributes
    
    let links: Set<LinkDataModel.ID>

    var body: some AttributedTextFormattingDefinition<Scope> {
        NormalizeFonts()
        LinksAreWhite(links: links)
        LinksHaveBlueBacks(links: links)
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

struct LinksAreWhite: AttributedTextValueConstraint {
    typealias Scope = ContentFormattingDefinition.Scope
    typealias AttributeKey = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute

    let links: Set<LinkDataModel.ID>

    func constrain(_ container: inout Attributes) {
        if let link = container.linkContent, links.contains(link) {
            container.foregroundColor = Color.primary
        } else {
            container.foregroundColor = nil
        }
    }
}

struct LinksHaveBlueBacks: AttributedTextValueConstraint {
    typealias Scope = ContentFormattingDefinition.Scope
    typealias AttributeKey = AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute

    let links: Set<LinkDataModel.ID>

    func constrain(_ container: inout Attributes) {
        if let link = container.linkContent, links.contains(link) {
            container.backgroundColor = Color.accentColor
        } else {
            container.backgroundColor = nil
        }
    }
}
