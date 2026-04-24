// @copyright André Trettin

import Foundation
import SwiftUI

@MainActor
public final class LinkReplaceController: Sendable {
    static let scheme: String = URL.appScheme

    public static func links(for text: String) -> [LinkReplaceModel] {
        var list: [LinkReplaceModel] = []
        let allLinks = ReferenceScanner.allUuidUrls(for: scheme, in: text)
        
        var seenTableId: [UUID: Int] = [:]
        list = allLinks.tables.map {
            let module = UserActivity.extractModule(from: $0.module)
            var linkNumber = Int($0.linkNumber) ?? 0
            var updatedLink = $0
            if $0.command == nil {
                linkNumber = seenTableId[$0.table, default: 0]
                seenTableId[$0.table] = linkNumber + 1
                updatedLink.linkNumber = "\(linkNumber)"
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
                updatedLink.linkNumber = "\(linkNumber)"
            }
            let markDown = updatedLink.markDown(for: scheme)
            let range = text.range(of: markDown) ?? text.startIndex..<text.endIndex
            return LinkReplaceModel(name: $0.name, module: module, linkNumber: linkNumber, itemId: $0.table, entryId: $0.entry, markDown: markDown, command: $0.command, range: range)
        }
        list.append(contentsOf: entryLinks)
        return list
    }

    public static func linksRepair(for text: inout String, linkControllable: LinkControllable?) -> [LinkReplaceModel] {
        var list: [LinkReplaceModel] = []
        let allLinks = ReferenceScanner.allUuidUrls(for: scheme, in: text)
        
        var seenTableId: [UUID: Int] = [:]
        list = allLinks.tables.map {
            let module = UserActivity.extractModule(from: $0.module)
            var linkNumber = Int($0.linkNumber) ?? 0
            var updatedLink = $0
            if $0.command == nil {
                linkNumber = seenTableId[$0.table, default: 0]
                seenTableId[$0.table] = linkNumber + 1
                if "\(linkNumber)" != updatedLink.linkNumber {
                    let prevMarkDown = updatedLink.markDown(for: scheme)
                    updatedLink.linkNumber = "\(linkNumber)"
                    let newMarkDown = updatedLink.markDown(for: scheme)
                    let ranges = text.ranges(of: prevMarkDown)
                    if linkNumber < ranges.count {
                        let replaceRange = ranges[linkNumber]
                        text = text.replacingOccurrences(of: prevMarkDown, with: newMarkDown, range: replaceRange)
                    } else {
                        text = text.replacingOccurrences(of: prevMarkDown, with: newMarkDown)
                    }
                }
            }
            let markDown = updatedLink.markDown(for: scheme)
            let range = text.range(of: markDown) ?? text.startIndex..<text.endIndex
//            let (updatedName, updatedMarkDown) = currentName(linkController: linkControllable, itemId: $0.table, entryId: nil, module: module) ?? ($0.name, markDown)
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
                if "\(linkNumber)" != updatedLink.linkNumber {
                    let prevMarkDown = updatedLink.markDown(for: scheme)
                    updatedLink.linkNumber = "\(linkNumber)"
                    let newMarkDown = updatedLink.markDown(for: scheme)
                    let ranges = text.ranges(of: prevMarkDown)
                    if linkNumber < ranges.count {
                        let replaceRange = ranges[linkNumber]
                        text = text.replacingOccurrences(of: prevMarkDown, with: newMarkDown, range: replaceRange)
                    } else {
                        text = text.replacingOccurrences(of: prevMarkDown, with: newMarkDown)
                    }
                }
            }
            let markDown = updatedLink.markDown(for: scheme)
            let range = text.range(of: markDown) ?? text.startIndex..<text.endIndex
            return LinkReplaceModel(name: $0.name, module: module, linkNumber: linkNumber, itemId: $0.table, entryId: $0.entry, markDown: markDown, command: $0.command, range: range)
        }
        list.append(contentsOf: entryLinks)
        return list
    }
    
    private static func currentName(linkController: LinkControllable?, itemId: UUID, entryId: UUID?, module: NetworkModules) -> (String, String)? {
        guard let itemControllable = linkController?.rootManager.itemRootController(for: module)?.itemControllable, let item = itemControllable.itemSync(for: itemId) else { return nil }
        if let entryId {
            return (item.urlName(entryId: entryId), item.url(linkNumber: 0, entryId: entryId))
        } else {
            return (item.urlName(), item.url(linkNumber: 0))
        }
    }

    public static func removeLinks(for text: String) -> String {
        let list = links(for: text)
        var result = text
        list.forEach {
            result = result.replacingOccurrences(of: $0.markDown, with: $0.name)
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

    public static func linkDetailModels(for text: String) -> [LinkReplaceModel] {
        let list = links(for: text)
        var names: Set<String> = []
        return list.map {
            var displayName = $0.name
            var counter = 1
            while names.contains(displayName) && counter < 100 {
                displayName = "\($0.name)-\(counter)"
                counter += 1
            }
            guard !names.contains(displayName) else { return $0 }
            names.insert(displayName)
            return LinkReplaceModel(name: "🔗[\(displayName)]", module: $0.module, linkNumber: $0.linkNumber, itemId: $0.itemId, entryId: $0.entryId, markDown: $0.markDown, command: $0.command, range: $0.range)
        }
    }

    public init(getter: @escaping () -> String, setter: @escaping (String) -> Void) {
        self.getter = getter
        self.setter = setter
        self.links = Self.linkDetailModels(for: getter())
    }

    private let getter: () -> String
    private let setter: (String) -> Void
    private var links: [LinkReplaceModel] = []


    public var editValue: Binding<String> {
        Binding { [weak self] in
            self?.getValue() ?? ""
        } set: { [weak self] updatedValue in
            self?.setValue(updatedValue)
        }
    }
    
    public func reset() {
        links = []
    }

    private func getValue() -> String {
        var value = getter()
        links.forEach {
            value = value.replacingOccurrences(of: $0.markDown, with: $0.name)
        }
        return value
    }

    private func setValue(_ updatedValue: String) {
        var value = updatedValue
        let newLinks = Self.linkDetailModels(for: value).filter { !links.contains($0) }
        if !newLinks.isEmpty {
            links.append(contentsOf: newLinks)
        }
        links.forEach {
            value = value.replacingOccurrences(of: $0.name, with: $0.markDown)
        }
        if getter() != value {
            setter(value)
        }
    }
}
