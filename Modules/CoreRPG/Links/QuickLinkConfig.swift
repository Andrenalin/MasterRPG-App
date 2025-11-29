// @copyright André Trettin

import SwiftUI

public struct LinkEntryModel {
    public init(reference: String, markdownUrl: String) {
        self.reference = reference
        self.markdownUrl = markdownUrl
    }

    public let reference: String
    public let markdownUrl: String
}

public struct QuickLinkConfig {
    public init(module: NetworkModules, title: LocalizedStringKey, name: @escaping ([UUID]) -> String) {
        self.module = module
        self.title = title
        self.name = name
    }

    public let module: NetworkModules
    public let title: LocalizedStringKey
    public let name: ([UUID]) -> String
}

