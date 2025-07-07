// @copyright André Trettin

import Foundation
import os.log

public enum ReferenceScanner {
    // MARK: - Markdown urls

    // [name](SCHEME://MODULE/LINKNO/TABLE)
    // [name](SCHEME://MODULE/LINKNO/TABLE/ENTRY)
    // [name](SCHEME://MODULE/LINKNO/TABLE/COMMAND)
    // [name](SCHEME://MODULE/LINKNO/TABLE/ENTRY/COMMAND)

    public static func allUuidUrls(for scheme: String, in text: String) -> AllReferenceLinks {
        let tables = parseUrlsTableWithCommand(for: scheme, in: text) + parseUrlsTable(for: scheme, in: text)
        let tableEntries = parseUrlsEntryWithCommand(for: scheme, in: text) + parseUrlsEntry(for: scheme, in: text)
        return AllReferenceLinks(tables: tables, tableEntries: tableEntries)
    }
}

private extension ReferenceScanner {
    static let namePattern = "[^\\]]*"
    static let uuidPattern = "[a-zA-Z0-9\\-]+"
    static let modulePattern = "[a-zA-Z]+"
    static let numberPattern = "[0-9]+"
    static let commandPattern = "[a-zA-Z]+"
    
    static func parseUrlsTable(for scheme: String, in content: String) -> [ReferenceTableLink] {
        var links: [ReferenceTableLink] = []
        let pattern = "\\[(?<Name>\(namePattern))\\]\\(\(scheme):\\/\\/(?<Module>\(modulePattern))\\/(?<Link>\(numberPattern))\\/(?<Table>\(uuidPattern))\\)"
        let results = RegularExpressionParser.parse(content, with: pattern, extract: ["Name", "Module", "Link", "Table"])
        for i in 0 ..< (results.count / 4) {
            let name = results[i * 4]
            let module = results[i * 4 + 1]
            let link = results[i * 4 + 2]
            let table = results[i * 4 + 3]
            if let tableUUID = UUID(uuidString: table) {
                links.append(ReferenceTableLink(name: name, module: module, linkNumber: link, table: tableUUID))
            } else {
                Logger.linkController.error("ReferenceScanner Parse error UUID nil for table:\(table). Link will be ignored")
            }
        }
        return links
    }
    
    static func parseUrlsTableWithCommand(for scheme: String, in content: String) -> [ReferenceTableLink] {
        var links: [ReferenceTableLink] = []
        let pattern = "\\[(?<Name>\(namePattern))\\]\\(\(scheme):\\/\\/(?<Module>\(modulePattern))\\/(?<Link>\(numberPattern))\\/(?<Table>\(uuidPattern))\\/(?<Command>\(commandPattern))\\)"
        let results = RegularExpressionParser.parse(content, with: pattern, extract: ["Name", "Module", "Link", "Table", "Command"])
        for i in 0 ..< (results.count / 5) {
            let name = results[i * 5]
            let module = results[i * 5 + 1]
            let link = results[i * 5 + 2]
            let table = results[i * 5 + 3]
            let command = results[i * 5 + 4]
            if let tableUUID = UUID(uuidString: table) {
                links.append(ReferenceTableLink(name: name, module: module, linkNumber: link, table: tableUUID, command: command))
            } else {
                Logger.linkController.error("ReferenceScanner Parse error UUID nil for table:\(table). Link will be ignored")
            }
        }
        return links
    }
    
    static func parseUrlsEntry(for scheme: String, in content: String) -> [ReferenceEntryLink] {
        var links: [ReferenceEntryLink] = []
        let pattern = "\\[(?<Name>\(namePattern))\\]\\(\(scheme):\\/\\/(?<Module>\(modulePattern))\\/(?<Link>\(numberPattern))\\/(?<Table>\(uuidPattern))\\/(?<Entry>\(uuidPattern))\\)"
        let results = RegularExpressionParser.parse(content, with: pattern, extract: ["Name", "Module", "Link", "Table", "Entry"])
        for i in 0 ..< (results.count / 5) {
            let name = results[i * 5]
            let module = results[i * 5 + 1]
            let link = results[i * 5 + 2]
            let table = results[i * 5 + 3]
            let entry = results[i * 5 + 4]
            if let tableUUID = UUID(uuidString: table), let entryUUID = UUID(uuidString: entry) {
                links.append(ReferenceEntryLink(name: name, module: module, linkNumber: link, table: tableUUID, entry: entryUUID))
            }
        }
        return links
    }
    
    static func parseUrlsEntryWithCommand(for scheme: String, in content: String) -> [ReferenceEntryLink] {
        var links: [ReferenceEntryLink] = []
        let pattern = "\\[(?<Name>\(namePattern))\\]\\(\(scheme):\\/\\/(?<Module>\(modulePattern))\\/(?<Link>\(numberPattern))\\/(?<Table>\(uuidPattern))\\/(?<Entry>\(uuidPattern))\\/(?<Command>\(commandPattern))\\)"
        let results = RegularExpressionParser.parse(content, with: pattern, extract: ["Name", "Module", "Link", "Table", "Entry", "Command"])
        for i in 0 ..< (results.count / 6) {
            let name = results[i * 6]
            let module = results[i * 6 + 1]
            let link = results[i * 6 + 2]
            let table = results[i * 6 + 3]
            let entry = results[i * 6 + 4]
            let command = results[i * 6 + 5]
            if let tableUUID = UUID(uuidString: table), let entryUUID = UUID(uuidString: entry) {
                links.append(ReferenceEntryLink(name: name, module: module, linkNumber: link, table: tableUUID, entry: entryUUID, command: command))
            } else {
                Logger.linkController.error("ReferenceScanner Parse error UUID nil for table:\(table) or entry:\(entry). Link will be ignored")
            }
        }
        return links
    }
}
