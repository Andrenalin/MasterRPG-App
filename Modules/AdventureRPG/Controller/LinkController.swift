// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI
import os.log
import AudioRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import MapRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import WeatherRPG

struct LinkController: Sendable {
    @MainActor init(rootManager: RootManager? = nil, itemController: ItemController) {
        self.rootManager = rootManager
        self.itemController = itemController
    }

    var rootManager: RootManager?
    let itemController: ItemController
    
    public var itemControllable: any ItemControllable { itemController }

    private var resolvedRootManager: RootManager {
        guard let rootManager else {
            preconditionFailure("Adventure LinkController requires rootManager to be set before use.")
        }
        return rootManager
    }
}

extension LinkController: LinkControllable {
    @MainActor public func handleTextLink(url: URL, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        let module = url.moduleIdentifier
        switch module {
        case .audio:
            return resolvedRootManager.audioRoot.linkControllable.handleTextLink(url: url, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
        case .dice:
            return resolvedRootManager.diceRoot.linkControllable.handleTextLink(url: url, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
        case .map:
            return resolvedRootManager.mapRoot.linkControllable.handleTextLink(url: url, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
        case .pdf:
            return resolvedRootManager.pdfRoot.linkControllable.handleTextLink(url: url, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
        case .photo:
            return resolvedRootManager.photoRoot.linkControllable.handleTextLink(url: url, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
        case .rule:
            return resolvedRootManager.ruleRoot.linkControllable.handleTextLink(url: url, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
        case .space:
            return resolvedRootManager.spaceRoot.linkControllable.handleTextLink(url: url, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
        case .table:
            return resolvedRootManager.tableRoot.linkControllable.handleTextLink(url: url, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
        case .value:
            return resolvedRootManager.characterRoot.linkControllable.handleTextLink(url: url, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
        case .weather:
            return resolvedRootManager.weatherRoot.linkControllable.handleTextLink(url: url, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
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
            return resolvedRootManager.audioRoot.linkControllable.toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
        case .dice:
            return resolvedRootManager.diceRoot.linkControllable.toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
        case .map:
            return resolvedRootManager.mapRoot.linkControllable.toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
        case .pdf:
            return resolvedRootManager.pdfRoot.linkControllable.toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
        case .photo:
            return resolvedRootManager.photoRoot.linkControllable.toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
        case .rule:
            return resolvedRootManager.ruleRoot.linkControllable.toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
        case .space:
            return resolvedRootManager.spaceRoot.linkControllable.toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
        case .table:
            return resolvedRootManager.tableRoot.linkControllable.toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
        case .value:
            return resolvedRootManager.characterRoot.linkControllable.toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
        case .weather:
            return resolvedRootManager.weatherRoot.linkControllable.toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
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
                await toggler?(itemId, itemControllable.config.module)
            }
            return text
        } else {
            if let toggler, entryId == nil, editAction == nil {
                Task { @MainActor in
                    await toggler(itemId, itemController.config.module)
                }
            }
            let item = itemController.itemOrEmpty(for: itemId)
            let showAction = toggler != nil ? "\(specialLink(linkType: .show, linkNumber: linkNumber, itemId: itemId, entryId: entryId)) " : ""
            let editLine = editAction?(ItemRowModel(itemId: itemId, entryId: entryId, typeId: itemController.config.module)) ?? false
            let removeAction = editLine ? " \(specialLink(linkType: .remove, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let description: String
            if let entryId {
                description = item[entryId].content
            } else {
                description = formatInlineDescription(description: item.description, entryCount: item.entries.count)
            }
            let result = "\(showAction) \(description)\(removeAction)"
            let url = generateLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId)
            return text.toggleLink(url: url, with: result)
        }
    }

    @MainActor public func repairLinks(_ links: [LinkReplaceModel], in content: String) -> String {
        var result = content
        for link in links {
            result = resolvedRootManager.audioRoot.linkControllable.repairLink(link, for: result, for: [.all])
            result = resolvedRootManager.diceRoot.linkControllable.repairLink(link, for: result, for: [.rules, .table, .value])
            result = resolvedRootManager.mapRoot.linkControllable.repairLink(link, for: result, for: [.all])
            result = resolvedRootManager.pdfRoot.linkControllable.repairLink(link, for: result, for: [.all])
            result = resolvedRootManager.photoRoot.linkControllable.repairLink(link, for: result, for: [.all])
            result = resolvedRootManager.ruleRoot.linkControllable.repairLink(link, for: result, for: [.all])
            result = resolvedRootManager.spaceRoot.linkControllable.repairLink(link, for: result, for: [.all])
            result = resolvedRootManager.tableRoot.linkControllable.repairLink(link, for: result, for: [.all])
            result = resolvedRootManager.characterRoot.linkControllable.repairLink(link, for: result, for: [.all])
            result = resolvedRootManager.weatherRoot.linkControllable.repairLink(link, for: result, for: [.all])
            result = repairLink(link, for: result, for: [.all])
        }
        return result
    }

    @MainActor public func validateLinks(on itemId: UUID) {
        guard let inspectedItem = itemController.itemSync(for: itemId), inspectedItem.displayState != 2, let replacedItem = itemController.copy(of: itemId) else { return }
    
        if let photoId = replacedItem.photoId {
            if !resolvedRootManager.photoRoot.linkControllable.validateLink(itemId: photoId) {
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
            itemController.replace(model: replacedItem, isInsert: false)
        }
        resetLinkRegister(replacedItem)
    }
}

extension LinkController {
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

extension LinkController {
    @MainActor func collectLinks(of module: NetworkModules, from itemId: UUID) -> [UUID] {
        guard let item = itemController.itemSync(for: itemId) else { return [] }
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
                    photoIds.append(contentsOf: resolvedRootManager.characterRoot.linkControllable.collectLinks(of: module, from: $0.itemId))
                case .map:
                    photoIds.append(contentsOf: resolvedRootManager.mapRoot.linkControllable.collectLinks(of: module, from: $0.itemId))
                case .weather:
                    photoIds.append(contentsOf: resolvedRootManager.weatherRoot.linkControllable.collectLinks(of: module, from: $0.itemId))
                case .adventure:
                    if $0.entryId == nil {
                        photoIds.append(contentsOf: resolvedRootManager.adventureRoot.linkControllable.collectLinks(of: module, from: $0.itemId))
                    }
                default:
                    break
                }
            }
        }
        return Array(Set(photoIds))
    }
}
