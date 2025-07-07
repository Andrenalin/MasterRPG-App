// @copyright André Trettin

import Foundation

public struct LinkReplaceModel: Hashable, Sendable {
    public init(name: String, module: NetworkModules, linkNumber: Int, itemId: UUID, entryId: UUID?, markDown: String, command: String?, range: Range<String.Index>) {
        self.name = name
        self.module = module
        self.linkNumber = linkNumber
        self.itemId = itemId
        self.entryId = entryId
        self.markDown = markDown
        self.command = command
        self.range = range
    }

    public let name: String
    public let module: NetworkModules
    public let linkNumber: Int
    public let itemId: UUID
    public let entryId: UUID?
    public let markDown: String
    public let command: String?
    public let range: Range<String.Index>

    var icon: String {
        if let command {
            LinkType(rawValue: command)?.icon ?? "questionmark.app.fill"
        } else {
            module.icon
        }
    }
}
