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
    // Dispatches by looking up the target module's root via `RootManager.rootModel(for:)`
    // instead of a hand-listed 9-case switch — matches the pattern `SheetController`
    // already uses in this module. See CODE_AUDIT §9.5.
    @MainActor public func handleTextLink(url: URL, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        let module = url.moduleIdentifier
        if module == .adventure {
            guard let itemId = url.itemId else { return text }
            guard let brokenLink = brokenTextLinkToggle(url: url, itemId: itemId, entryId: nil, in: text) else {
                return toggleTextLink(linkNumber: url.linkNumber, itemId: itemId, entryId: url.childId, command: url.commandKey, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
            }
            return brokenLink
        }
        guard let linkControllable = resolvedRootManager.rootModel(for: module)?.linkControllable else { return text }
        return linkControllable.handleTextLink(url: url, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction)
    }

    @MainActor
    public func toggleLink(module: NetworkModules, linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?) -> String {
        guard module != .adventure, let linkControllable = resolvedRootManager.rootModel(for: module)?.linkControllable else {
            return toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
        }
        return linkControllable.toggleLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command)
    }

    @MainActor
    public func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        if let command {
            if command == LinkType.remove.rawValue {
                let url = generateLink(linkNumber: linkNumber - LinkType.remove.linkNumberAddition, itemId: itemId, entryId: entryId)
                return text.toggleLink(url: url, with: name(for: itemId, entryId: entryId), remove: true)
            }
            LinkActionTasks.run {
                await toggler?(itemId, itemControllable.config.module)
            }
            return text
        } else {
            let item = itemController.itemOrEmpty(for: itemId)
            let showAction = toggler != nil ? "\(specialLink(linkType: .show, linkNumber: linkNumber, itemId: itemId, entryId: entryId)) " : ""
            let removeAction = autoToggleAndRemoveAction(linkNumber: linkNumber, itemId: itemId, entryId: entryId, toggler: toggler, editAction: editAction)
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
            // Each module's `repairLink` ignores a link of another module, so only the one that owns
            // the link is asked. See CODE_AUDIT_Adventure §7.1, CODE_AUDIT_26 §3.10.
            switch link.module {
            case .audio: result = resolvedRootManager.audioRoot.linkControllable.repairLink(link, for: result, for: [.all])
            case .dice: result = resolvedRootManager.diceRoot.linkControllable.repairLink(link, for: result, for: [.rules, .table, .value])
            case .map: result = resolvedRootManager.mapRoot.linkControllable.repairLink(link, for: result, for: [.all])
            case .pdf: result = resolvedRootManager.pdfRoot.linkControllable.repairLink(link, for: result, for: [.all])
            case .photo: result = resolvedRootManager.photoRoot.linkControllable.repairLink(link, for: result, for: [.all])
            case .rule: result = resolvedRootManager.ruleRoot.linkControllable.repairLink(link, for: result, for: [.all])
            case .space: result = resolvedRootManager.spaceRoot.linkControllable.repairLink(link, for: result, for: [.all])
            case .table: result = resolvedRootManager.tableRoot.linkControllable.repairLink(link, for: result, for: [.all])
            case .value: result = resolvedRootManager.characterRoot.linkControllable.repairLink(link, for: result, for: [.all])
            case .weather: result = resolvedRootManager.weatherRoot.linkControllable.repairLink(link, for: result, for: [.all])
            default: result = repairLink(link, for: result, for: [.all])
            }
        }
        return result
    }

    @MainActor public func validateLinks(on itemId: UUID) {
        guard let inspectedItem = itemController.itemSync(for: itemId), !inspectedItem.isHidden, let replacedItem = itemController.copy(of: itemId) else { return }

        if let photoId = replacedItem.photoId {
            if !resolvedRootManager.photoRoot.linkControllable.validateLink(itemId: photoId) {
                Logger.linkController.warning("Adventure: \(replacedItem.name, privacy: .private) --> Photo \(photoId, privacy: .public) is gone. Reset PhotoId, no recovery possible.")
                replacedItem.photoId = nil
            }
        }

        if let diceId = replacedItem.diceId {
            if !resolvedRootManager.diceRoot.linkControllable.validateLink(itemId: diceId) {
                Logger.linkController.warning("Adventure: \(replacedItem.name, privacy: .private) --> Dice \(diceId, privacy: .public) is gone. Reset DiceId, no recovery possible.")
                replacedItem.diceId = nil
            }
        }

        let validTablePlayers = replacedItem.tablePlayers.filter {
            resolvedRootManager.characterRoot.linkControllable.validateLink(itemId: $0.characterId)
        }
        if validTablePlayers.count != replacedItem.tablePlayers.count {
            Logger.linkController.warning("Adventure: \(replacedItem.name, privacy: .private) --> \(replacedItem.tablePlayers.count - validTablePlayers.count, privacy: .public) table player Characters are gone. Removed, no recovery possible.")
            replacedItem.tablePlayers = validTablePlayers
        }

        for entry in inspectedItem.entries {
            var validatedEntry = entry

            // A group entry whose hidden adventure is gone points at nothing: the group link is
            // cleared. See CODE_AUDIT_26 §5.98.
            if let groupId = entry.adventureId, itemController.itemSync(for: groupId) == nil {
                Logger.linkController.warning("Adventure: \(replacedItem.name, privacy: .private) --> group \(groupId, privacy: .public) is gone. Group link removed, no recovery possible.")
                validatedEntry.adventureId = nil
            }

            let links = LinkReplaceController.links(for: entry.content)
            validatedEntry.content = repairLinks(links, in: validatedEntry.content)

            if !entry.isSame(validatedEntry) {
                replacedItem[entry.id]  = validatedEntry
            }
        }
        if !replacedItem.isSame(inspectedItem) {
            Logger.linkController.info("Adventure: \(replacedItem.name, privacy: .private) will be replaced from repairing links.")
            itemController.replace(model: replacedItem, isInsert: false)
        }
        resetLinkRegister(replacedItem)
    }
}

extension LinkController {
    @MainActor func collectLinks(of module: NetworkModules, from itemId: UUID) -> [UUID] {
        collectLinks(of: module, from: itemId, visited: [])
    }

    /// `visited` guards against adventure-to-adventure link cycles (two adventures
    /// linking to each other at the item level recurse through this exact function via
    /// the `.adventure` case below), which previously crashed via stack overflow with no
    /// base case. Threaded as a value (not `inout`) so it only ever grows within a single
    /// traversal and never leaks across sibling calls. See CODE_AUDIT §5.1.
    ///
    /// Also gates photo-id collection on `module == .photo` — the function is a public
    /// `LinkControllable` requirement any module can call with any `module` value, and
    /// previously always collected photo links regardless of what was actually asked for.
    /// See CODE_AUDIT §5.2.
    @MainActor private func collectLinks(of module: NetworkModules, from itemId: UUID, visited: Set<UUID>) -> [UUID] {
        guard !visited.contains(itemId), let item = itemController.itemSync(for: itemId) else { return [] }
        var visited = visited
        visited.insert(itemId)

        var linkIds: [UUID] = []
        if module == .photo, let id = item.photoId {
            linkIds.append(id)
        }
        // The item-level dice and the table players' Characters are links of the item as well.
        // See CODE_AUDIT_26 §5.97.
        if module == .dice, let id = item.diceId {
            linkIds.append(id)
        }
        if module == .value {
            linkIds.append(contentsOf: item.tablePlayers.map(\.characterId))
        }
        // A group entry stands for a hidden adventure whose own links count as well.
        for groupId in item.entries.compactMap(\.adventureId) {
            linkIds.append(contentsOf: collectLinks(of: module, from: groupId, visited: visited))
        }
        item.entries.forEach {
            let links = LinkReplaceController.links(for: $0.content)
            links.forEach {
                switch $0.module {
                case .photo:
                    if module == .photo {
                        linkIds.append($0.itemId)
                    }
                case .adventure:
                    // Recurse in-process (not through `linkControllable`) so the
                    // visited-set guard above actually catches the cycle.
                    if $0.entryId == nil {
                        linkIds.append(contentsOf: collectLinks(of: module, from: $0.itemId, visited: visited))
                    }
                default:
                    if let linkControllable = resolvedRootManager.rootModel(for: $0.module)?.linkControllable {
                        linkIds.append(contentsOf: linkControllable.collectLinks(of: module, from: $0.itemId))
                    }
                }
            }
        }
        return Array(Set(linkIds))
    }
}
