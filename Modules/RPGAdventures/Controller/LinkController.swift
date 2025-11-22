// @copyright André Trettin

import AndrenalinKit
import Foundation
import SwiftUI
import os.log
import AudioRPG
import RPGDie
import RPGPdfs
import PhotoRPG
import RPGMaps
import SpaceRPG
import RPGTables
import RPGValues
import RPGWeathers

public struct LinkController: Sendable {
    weak var root: AdventureRootModel!
    let itemController: ItemController

    public var itemControllable: any ItemControllable {
        itemController as ItemController
    }
}

extension LinkController: LinkControllable {
    @MainActor
    public func handleTextLink(url: URL, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        let module = url.moduleIdentifier
        switch module {
        case .audio:
            return root.audioRoot.linkController.handleTextLink(url: url, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
        case .dice:
            return root.diceRoot.linkController.handleTextLink(url: url, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
        case .map:
            return root.mapRoot.linkController.handleTextLink(url: url, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
        case .pdf:
            return root.pdfRoot.linkController.handleTextLink(url: url, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
        case .photo:
            return root.photoRoot.linkController.handleTextLink(url: url, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
        case .space:
            return root.spaceRoot.linkController.handleTextLink(url: url, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
        case .table:
            return root.tableRoot.linkController.handleTextLink(url: url, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
        case .value:
            return root.valueRoot.linkController.handleTextLink(url: url, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
        case .weather:
            return root.weatherRoot.linkController.handleTextLink(url: url, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
        case .adventure:
            guard let itemId = url.itemId else { return text }
            guard let brokenLink = brokenTextLinkToggle(url: url, itemId: itemId, entryId: nil, in: text) else {
                let linkText = toggleTextLink(linkNumber: url.linkNumber, itemId: itemId, entryId: url.childId, command: url.commandKey, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
                return linkText
            }
            return brokenLink
        default:
            return text
        }
    }

    @MainActor
    public func toggleLink(module: NetworkModules, linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?) -> String {
        switch module {
        case .audio:
            return root.audioRoot.linkController.toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
        case .dice:
            return root.diceRoot.linkController.toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
        case .map:
            return root.mapRoot.linkController.toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
        case .pdf:
            return root.pdfRoot.linkController.toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
        case .photo:
            return root.photoRoot.linkController.toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
        case .space:
            return root.spaceRoot.linkController.toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
        case .table:
            return root.tableRoot.linkController.toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
        case .value:
            return root.valueRoot.linkController.toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
        case .weather:
            return root.weatherRoot.linkController.toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
        default:
            return toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
        }
    }

    @MainActor
    public func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        if let command {
            if command == LinkType.remove.rawValue {
                let url = generateLink(linkNumber: linkNumber - LinkType.remove.linkNumberAddition, itemId: itemId, entryId: entryId)
                return text.toggleLink(url: url, with: name(for: itemId, entryId: entryId), remove: true)
            }
            Task { @MainActor in
                await toggler?(itemId, itemControllable.itemDataModel.networkModule)
            }
            return text
        } else {
            if let toggler, entryId == nil, editAction == nil {
                Task { @MainActor in
                    await toggler(itemId, itemController.itemDataModel.networkModule)
                }
            }
            let item = itemController.itemOrEmpty(for: itemId)
            let showAction = toggler != nil ? "\(specialLink(linkType: .show, linkNumber: linkNumber, itemId: itemId, entryId: entryId)) " : ""
            let editLine = editAction?(ItemRowModel(itemId: itemId, entryId: entryId, typeId: itemController.itemDataModel.networkModule)) ?? false
            let removeAction = editLine ? " \(specialLink(linkType: .remove, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let description: String
            if let entryId {
                description = item[entryId].content
            } else {
                description = "\(item.name) / \(item.description) / \(item.entries.count) Entries"
            }
            let result = "\(showAction) \(description)\(removeAction)"
            let url = generateLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId)
            return text.toggleLink(url: url, with: result)
        }
    }

    @MainActor public func repairLinks(_ links: [LinkReplaceModel], in content: String) -> String {
        var result = content
        for link in links {
            result = root.audioRoot.linkController.repairLink(link, for: result, for: [.all])
            result = root.diceRoot.linkController.repairLink(link, for: result, for: [.rules, .table, .value])
            result = root.mapRoot.linkController.repairLink(link, for: result, for: [.all])
            result = root.pdfRoot.linkController.repairLink(link, for: result, for: [.all])
            result = root.photoRoot.linkController.repairLink(link, for: result, for: [.all])
            result = root.spaceRoot.linkController.repairLink(link, for: result, for: [.all])
            result = root.tableRoot.linkController.repairLink(link, for: result, for: [.all])
            result = root.valueRoot.linkController.repairLink(link, for: result, for: [.all])
            result = root.weatherRoot.linkController.repairLink(link, for: result, for: [.all])
            result = repairLink(link, for: result, for: [.all])
        }
        return result
    }

    @MainActor public func validateLinks(on itemId: UUID) {
        guard let inspectedItem = itemController.itemSync(for: itemId), let replacedItem = itemController.copy(of: itemId) else { return }
    
        if let photoId = replacedItem.photoId {
            if !root.photoRoot.linkController.validateLink(itemId: photoId) {
                Logger.linkController.warning("Adventure: \(replacedItem.name, privacy: .public) --> Photo \(photoId, privacy: .public) is gone. Reset PhotoId, no recovery possible.")
                replacedItem.photoId = nil
            }
        }

        for entry in inspectedItem.entries {
            var validatedEntry = entry

            let links = entry.links(for: entry.content)
            validatedEntry.content = repairLinks(links, in: validatedEntry.content)

            if !entry.isSame(validatedEntry) {
                replacedItem[entry.id]  = validatedEntry
            }
        }
        if !replacedItem.isSame(inspectedItem) {
            Logger.linkController.info("Adventure: \(replacedItem.name, privacy: .public) will be replaced from reparing links.")
            itemController.replace(model: replacedItem, isInsert: false, shouldRepairLinks: true)
        }
    }    
}

public extension LinkController {
    @MainActor
    func link(for module: NetworkModules) -> [LinkEntryModel] {
        itemController.itemDataModel.items.map { itemController.itemOrEmpty(for: $0) }.sorted(by: { $0.name.count > $1.name.count })
            .map { LinkEntryModel(reference: $0.name, markdownUrl: $0.url(linkNumber: 0)) }
    }

    @MainActor
    func linkEntries(for itemId: UUID) -> [LinkEntryModel] {
        let item = itemController.itemOrEmpty(for: itemId)
        return item.entries
            .sorted(by: { $0.name.count > $1.name.count })
            .map { LinkEntryModel(reference: $0.name, markdownUrl: item.url(linkNumber: 0, entryId: $0.id)) }
    }
}

public extension LinkController {
    @MainActor
    func toggleSheet(itemId: UUID, level: Int, module: NetworkModules) -> SheetModel? {
        switch module {
        case .audio:
            return root.audioRoot.linkController.toggleSheet(itemId: itemId, level: level, module: module)
        case .dice:
            return root.diceRoot.linkController.toggleSheet(itemId: itemId, level: level, module: module)
        case .map:
            return root.mapRoot.linkController.toggleSheet(itemId: itemId, level: level, module: module)
        case .pdf:
            return root.pdfRoot.linkController.toggleSheet(itemId: itemId, level: level, module: module)
        case .photo:
            return root.photoRoot.linkController.toggleSheet(itemId: itemId, level: level, module: module)
        case .space:
            return root.spaceRoot.linkController.toggleSheet(itemId: itemId, level: level, module: module)
        case .table:
            return root.tableRoot.linkController.toggleSheet(itemId: itemId, level: level, module: module)
        case .value:
            return root.valueRoot.linkController.toggleSheet(itemId: itemId, level: level, module: module)
        case .weather:
            return root.weatherRoot.linkController.toggleSheet(itemId: itemId, level: level, module: module)
        default:
            return SheetController(root: root).sheet(for: itemId, level: level)
        }
    }
}

public extension LinkController {
    @MainActor func collectLinks(of module: NetworkModules, from itemId: UUID) -> [UUID] {
        guard let item = root.itemController.itemSync(for: itemId) else { return [] }
        var photoIds: [UUID] = []
        if let id = item.photoId {
            photoIds.append(id)
        }
        item.entries.forEach {
            let links = $0.links(for: $0.content)
            links.forEach {
                switch $0.module {
                case .photo:
                    photoIds.append($0.itemId)
                case .value:
                    photoIds.append(contentsOf: root.valueRoot.linkController.collectLinks(of: module, from: $0.itemId))
                case .map:
                    photoIds.append(contentsOf: root.mapRoot.linkController.collectLinks(of: module, from: $0.itemId))
                case .weather:
                    photoIds.append(contentsOf: root.weatherRoot.linkController.collectLinks(of: module, from: $0.itemId))
                case .adventure:
                    if $0.entryId == nil {
                        photoIds.append(contentsOf: root.linkController.collectLinks(of: module, from: $0.itemId))
                    }
                default:
                    break
                }
            }
        }
        return Array(Set(photoIds))
    }
}
