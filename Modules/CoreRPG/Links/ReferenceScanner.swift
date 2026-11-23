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
        guard text.contains("\(scheme)://") else {
            return AllReferenceLinks(tables: [], tableEntries: [])
        }

        let tables = parseUrlsTableWithCommand(for: scheme, in: text) + parseUrlsTable(for: scheme, in: text)
        let tableEntries = parseUrlsEntryWithCommand(for: scheme, in: text) + parseUrlsEntry(for: scheme, in: text)
        return AllReferenceLinks(tables: tables, tableEntries: tableEntries)
    }
    
}

private extension ReferenceScanner {
    /// A label with backslash escapes (`LinkBuilder.escapedLabel`): `\x` or any character that is
    /// neither `]` nor `\`.
    static let namePattern = "(?:\\\\.|[^\\]\\\\])*"
    static let uuidPattern = "[a-zA-Z0-9\\-]+"
    static let modulePattern = "[a-zA-Z]+"
    static let numberPattern = "[0-9]+"
    static let commandPattern = "[a-zA-Z]+"
    
    /// One link match; `entry`/`command` are set when the pattern has those segments.
    struct LinkMatch {
        let name: String
        let module: String
        let link: String
        let table: String
        let entry: String?
        let command: String?
    }

    /// The one parser behind the four link shapes: `TABLE`, `TABLE/COMMAND`, `TABLE/ENTRY` and
    /// `TABLE/ENTRY/COMMAND` differ only in their optional segments. Only a table segment that
    /// is not a UUID is logged: a command link (`…/TABLE/Roll`) also matches the entry shape,
    /// and its non-UUID "entry" is expected. See CODE_AUDIT_19 §9.18.
    static func parseLinks(for scheme: String, in content: String, hasEntry: Bool, hasCommand: Bool) -> [LinkMatch] {
        var pattern = "\\[(?<Name>\(namePattern))\\]\\(\(scheme):\\/\\/(?<Module>\(modulePattern))\\/(?<Link>\(numberPattern))\\/(?<Table>\(uuidPattern))"
        var groups = ["Name", "Module", "Link", "Table"]
        if hasEntry {
            pattern += "\\/(?<Entry>\(uuidPattern))"
            groups.append("Entry")
        }
        if hasCommand {
            pattern += "\\/(?<Command>\(commandPattern))"
            groups.append("Command")
        }
        pattern += "\\)"
        let results = RegularExpressionParser.parse(content, with: pattern, extract: groups)
        return stride(from: 0, to: results.count - groups.count + 1, by: groups.count).compactMap { start in
            let match = LinkMatch(
                name: LinkBuilder.unescapedLabel(results[start]),
                module: results[start + 1],
                link: results[start + 2],
                table: results[start + 3],
                entry: hasEntry ? results[start + 4] : nil,
                command: hasCommand ? results[start + groups.count - 1] : nil
            )
            guard UUID(uuidString: match.table) != nil else {
                Logger.linkController.error("ReferenceScanner Parse error UUID nil for table:\(match.table). Link will be ignored")
                return nil
            }
            return match
        }
    }

    static func parseUrlsTable(for scheme: String, in content: String) -> [ReferenceTableLink] {
        tableLinks(parseLinks(for: scheme, in: content, hasEntry: false, hasCommand: false))
    }

    static func parseUrlsTableWithCommand(for scheme: String, in content: String) -> [ReferenceTableLink] {
        tableLinks(parseLinks(for: scheme, in: content, hasEntry: false, hasCommand: true))
    }

    static func parseUrlsEntry(for scheme: String, in content: String) -> [ReferenceEntryLink] {
        entryLinks(parseLinks(for: scheme, in: content, hasEntry: true, hasCommand: false))
    }

    static func parseUrlsEntryWithCommand(for scheme: String, in content: String) -> [ReferenceEntryLink] {
        entryLinks(parseLinks(for: scheme, in: content, hasEntry: true, hasCommand: true))
    }

    static func tableLinks(_ matches: [LinkMatch]) -> [ReferenceTableLink] {
        matches.compactMap { match in
            guard let table = UUID(uuidString: match.table) else { return nil }
            return ReferenceTableLink(name: match.name, module: match.module, linkNumber: match.link, table: table, command: match.command)
        }
    }

    static func entryLinks(_ matches: [LinkMatch]) -> [ReferenceEntryLink] {
        matches.compactMap { match in
            guard let table = UUID(uuidString: match.table),
                  let entryText = match.entry,
                  let entry = UUID(uuidString: entryText) else { return nil }
            return ReferenceEntryLink(name: match.name, module: match.module, linkNumber: match.link, table: table, entry: entry, command: match.command)
        }
    }
}
