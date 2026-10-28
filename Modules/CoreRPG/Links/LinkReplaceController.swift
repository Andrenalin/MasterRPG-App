// @copyright André Trettin

import Foundation
import SwiftUI

@MainActor
public final class LinkReplaceController: Sendable {
    static let scheme: String = URL.appScheme

    public static func links(for text: String) -> [LinkReplaceModel] {
        var scanned = text
        return numberedLinks(in: &scanned, repairs: false)
    }

    /// The links of `text`, numbered per table and entry in order of appearance, with every link
    /// whose stored number disagrees rewritten in `text`.
    public static func linksRepair(for text: inout String) -> [LinkReplaceModel] {
        numberedLinks(in: &text, repairs: true)
    }

    /// The one numbering loop behind `links(for:)` and `linksRepair(for:)`: a link without a
    /// command is numbered by how often its table (or table entry) appeared before it. With
    /// `repairs`, a stored number that differs is also corrected in `text`.
    ///
    /// Identical links in one text (the same stored number twice, as in the quick editor) are
    /// told apart by their position: the n-th link with a given markdown is the n-th occurrence
    /// of that markdown. Locating them with a plain `range(of:)` found the first occurrence for
    /// all of them. See CODE_AUDIT_20 §9.6.
    private static func numberedLinks(in text: inout String, repairs: Bool) -> [LinkReplaceModel] {
        let source = text
        let allLinks = ReferenceScanner.allUuidUrls(for: scheme, in: source)

        var numbered: [NumberedLink] = []
        var seenTableId: [UUID: Int] = [:]
        for link in allLinks.tables {
            var updatedLink = link
            var linkNumber = Int(link.linkNumber) ?? 0
            if link.command == nil {
                linkNumber = seenTableId[link.table, default: 0]
                seenTableId[link.table] = linkNumber + 1
                updatedLink.linkNumber = "\(linkNumber)"
            }
            numbered.append(NumberedLink(
                name: link.name, module: UserActivity.extractModule(from: link.module), linkNumber: linkNumber,
                itemId: link.table, entryId: nil, command: link.command,
                original: link.markDown(for: scheme), markDown: updatedLink.markDown(for: scheme)
            ))
        }
        var seenEntryId: [UUID: [UUID: Int]] = [:]
        for link in allLinks.tableEntries {
            var updatedLink = link
            var linkNumber = Int(link.linkNumber) ?? 0
            if link.command == nil {
                var tableIds = seenEntryId[link.table, default: [:]]
                linkNumber = tableIds[link.entry, default: 0]
                tableIds[link.entry] = linkNumber + 1
                seenEntryId[link.table] = tableIds
                updatedLink.linkNumber = "\(linkNumber)"
            }
            numbered.append(NumberedLink(
                name: link.name, module: UserActivity.extractModule(from: link.module), linkNumber: linkNumber,
                itemId: link.table, entryId: link.entry, command: link.command,
                original: link.markDown(for: scheme), markDown: updatedLink.markDown(for: scheme)
            ))
        }

        var sourceOccurrences = MarkDownOccurrences(text: source)
        var ranges = numbered.map { sourceOccurrences.next($0.original) }
        if repairs {
            text = rewritten(source, numbered: numbered, ranges: ranges)
            var repairedOccurrences = MarkDownOccurrences(text: text)
            ranges = numbered.map { repairedOccurrences.next($0.markDown) }
        }

        return zip(numbered, ranges).map { link, range in
            LinkReplaceModel(name: link.name, module: link.module, linkNumber: link.linkNumber, itemId: link.itemId, entryId: link.entryId, markDown: link.markDown, command: link.command, range: range ?? text.startIndex..<text.endIndex)
        }
    }

    /// `source` with every link whose stored number disagrees rewritten in place.
    private static func rewritten(_ source: String, numbered: [NumberedLink], ranges: [Range<String.Index>?]) -> String {
        let fixes = zip(numbered, ranges).compactMap { link, range in
            range.flatMap { link.original == link.markDown ? nil : (range: $0, text: link.markDown) }
        }
        return source.replacing(ranges: fixes)
    }

    private struct NumberedLink {
        let name: String
        let module: NetworkModules
        let linkNumber: Int
        let itemId: UUID
        let entryId: UUID?
        let command: String?
        /// The link as written in the text, and as it reads with its computed number.
        let original: String
        let markDown: String
    }
}

/// Hands out the occurrences of a markdown string in a text one after the other, so that
/// identical links are told apart by their position: the n-th request for a markdown returns
/// the n-th occurrence of it.
struct MarkDownOccurrences {
    init(text: String) {
        self.text = text
    }

    let text: String
    private var ranges: [String: [Range<String.Index>]] = [:]
    private var handedOut: [String: Int] = [:]

    mutating func next(_ markDown: String) -> Range<String.Index>? {
        let occurrences: [Range<String.Index>]
        if let cached = ranges[markDown] {
            occurrences = cached
        } else {
            occurrences = text.ranges(of: markDown)
            ranges[markDown] = occurrences
        }
        let index = handedOut[markDown, default: 0]
        handedOut[markDown] = index + 1
        return index < occurrences.count ? occurrences[index] : nil
    }
}
