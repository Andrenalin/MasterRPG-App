// @copyright André Trettin

import SwiftUI

public struct ReferenceTableLink: Equatable, Hashable {
    public let name: String
    public let module: String
    public var linkNumber: String
    public let table: UUID
    public let command: String?

    public init(name: String, module: String, linkNumber: String, table: UUID, command: String? = nil) {
        self.name = name
        self.module = module
        self.linkNumber = linkNumber
        self.table = table
        self.command = command
    }

    public func url(for scheme: String) -> String {
        "(\(scheme)://\(module)/\(linkNumber)/\(table.uuidString)\(command != nil ? "/\(command!)" : ""))"
    }

    public func markDown(for scheme: String) -> String {
        "[\(name)]\(url(for: scheme))"
    }
}

public struct ReferenceEntryLink: Equatable, Hashable {
    public let name: String
    public let module: String
    public var linkNumber: String
    public let table: UUID
    public let entry: UUID
    public let command: String?

    public init(name: String, module: String, linkNumber: String, table: UUID, entry: UUID, command: String? = nil) {
        self.name = name
        self.module = module
        self.linkNumber = linkNumber
        self.table = table
        self.entry = entry
        self.command = command
    }

    public func url(for scheme: String) -> String {
        "(\(scheme)://\(module)/\(linkNumber)/\(table.uuidString)/\(entry.uuidString)\(command != nil ? "/\(command!)" : ""))"
    }

    public func markDown(for scheme: String) -> String {
        "[\(name)]\(url(for: scheme))"
    }
}

public struct AllReferenceLinks: Equatable, Hashable {
    public let tables: [ReferenceTableLink]
    public let tableEntries: [ReferenceEntryLink]

    public init(tables: [ReferenceTableLink], tableEntries: [ReferenceEntryLink]) {
        self.tables = tables
        self.tableEntries = tableEntries
    }
}
