// @copyright André Trettin

import Foundation
import SwiftUI

struct ContentFormattingDefinition: AttributedTextFormattingDefinition {
    typealias Scope = AttributeScopes.ContentAttributes
    
    let links: Set<LinkDataModel.ID>
    var colorScheme: ColorScheme = .light

    var body: some AttributedTextFormattingDefinition<Scope> {
        NormalizeFonts()
        LinksAreAdaptive(links: links, colorScheme: colorScheme)
        LinksHaveAdaptiveBacks(links: links, colorScheme: colorScheme)
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

struct LinksAreAdaptive: AttributedTextValueConstraint {
    typealias Scope = ContentFormattingDefinition.Scope
    typealias AttributeKey = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute

    let links: Set<LinkDataModel.ID>
    let colorScheme: ColorScheme

    func constrain(_ container: inout Attributes) {
        if let link = container.linkContent, links.contains(link) {
            // Adaptive color based on color scheme and accent color
            container.foregroundColor = colorScheme == .dark ? .white : .primary
        } else {
            container.foregroundColor = nil
        }
    }
}

struct LinksHaveAdaptiveBacks: AttributedTextValueConstraint {
    typealias Scope = ContentFormattingDefinition.Scope
    typealias AttributeKey = AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute

    let links: Set<LinkDataModel.ID>
    let colorScheme: ColorScheme

    func constrain(_ container: inout Attributes) {
        if let link = container.linkContent, links.contains(link) {
            // Use accent color with adaptive opacity
            container.backgroundColor = Color.accentColor.opacity(colorScheme == .dark ? 0.6 : 0.8)
        } else {
            container.backgroundColor = nil
        }
    }
}
