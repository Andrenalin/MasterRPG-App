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
