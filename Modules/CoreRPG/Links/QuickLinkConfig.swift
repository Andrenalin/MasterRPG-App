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

