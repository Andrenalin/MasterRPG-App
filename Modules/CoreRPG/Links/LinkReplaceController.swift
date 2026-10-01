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
    /// See CODE_AUDIT_20 §9.6.
    private static func numberedLinks(in text: inout String, repairs: Bool) -> [LinkReplaceModel] {
        let allLinks = ReferenceScanner.allUuidUrls(for: scheme, in: text)

        var seenTableId: [UUID: Int] = [:]
        var list = allLinks.tables.map {
            let module = UserActivity.extractModule(from: $0.module)
            var linkNumber = Int($0.linkNumber) ?? 0
            var updatedLink = $0
            if $0.command == nil {
                linkNumber = seenTableId[$0.table, default: 0]
                seenTableId[$0.table] = linkNumber + 1
                let previousMarkDown = updatedLink.markDown(for: scheme)
                let needsRepair = "\(linkNumber)" != updatedLink.linkNumber
                updatedLink.linkNumber = "\(linkNumber)"
                if repairs, needsRepair {
                    replace(occurrence: linkNumber, of: previousMarkDown, with: updatedLink.markDown(for: scheme), in: &text)
                }
            }
            let markDown = updatedLink.markDown(for: scheme)
            let range = text.range(of: markDown) ?? text.startIndex..<text.endIndex
            return LinkReplaceModel(name: $0.name, module: module, linkNumber: linkNumber, itemId: $0.table, entryId: nil, markDown: markDown, command: $0.command, range: range)
        }
        var seenEntryId: [UUID: [UUID: Int]] = [:]
        let entryLinks = allLinks.tableEntries.map {
            let module = UserActivity.extractModule(from: $0.module)
            var tableIds = seenEntryId[$0.table, default: [:]]
            var linkNumber = Int($0.linkNumber) ?? 0
            var updatedLink = $0
            if $0.command == nil {
                linkNumber = tableIds[$0.entry, default: 0]
                tableIds[$0.entry] = linkNumber + 1
                seenEntryId[$0.table] = tableIds
                let previousMarkDown = updatedLink.markDown(for: scheme)
                let needsRepair = "\(linkNumber)" != updatedLink.linkNumber
                updatedLink.linkNumber = "\(linkNumber)"
                if repairs, needsRepair {
                    replace(occurrence: linkNumber, of: previousMarkDown, with: updatedLink.markDown(for: scheme), in: &text)
                }
            }
            let markDown = updatedLink.markDown(for: scheme)
            let range = text.range(of: markDown) ?? text.startIndex..<text.endIndex
            return LinkReplaceModel(name: $0.name, module: module, linkNumber: linkNumber, itemId: $0.table, entryId: $0.entry, markDown: markDown, command: $0.command, range: range)
        }
        list.append(contentsOf: entryLinks)
        return list
    }

    /// Replaces the `occurrence`-th appearance of `previous` in `text` with `new`, or every
    /// appearance when there are fewer.
    private static func replace(occurrence: Int, of previous: String, with new: String, in text: inout String) {
        let ranges = text.ranges(of: previous)
        if occurrence < ranges.count {
            // `.replacing(_:with:subrange:)` was tried here first but discovered
            // (via a failing test) to replace every occurrence in the whole
            // string, silently ignoring `subrange`, in this Swift toolchain —
            // not a scoped search at all. `replaceSubrange(_:with:)`
            // unambiguously replaces only this one occurrence.
            text.replaceSubrange(ranges[occurrence], with: new)
        } else {
            text = text.replacing(previous, with: new)
        }
    }

    public static func removeLinks(for text: String) -> String {
        let list = links(for: text)
        var result = text
        list.forEach {
            result = result.replacing($0.markDown, with: $0.name)
        }
        return result
    }

    public static func updateLinks(for text: String) -> String {
        let list = links(for: text)
        var result = text
        list.forEach {
            var entryPart = ""
            if let entryId = $0.entryId {
                entryPart = "/\(entryId.uuidString)"
            }
            let oldLink = "[\($0.name)](\(scheme)://\($0.module.token)/\($0.itemId.uuidString)\(entryPart))"

            result = result.replacing(oldLink, with: $0.markDown, maxReplacements: 1)
        }
        return result
    }
}
