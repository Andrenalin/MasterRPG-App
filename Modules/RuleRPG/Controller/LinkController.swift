// @copyright André Trettin

import CoreRPG
import Foundation
import os

@MainActor
private final class RuleLinkRootReference: Sendable {
    var rootManager: RootManager?
}

struct LinkController: Sendable {
    @MainActor
    init(itemController: ItemController, gameController: GameController) {
        self.itemController = itemController
        self.gameController = gameController
        rootReference = RuleLinkRootReference()
    }

    let itemController: ItemController
    let gameController: GameController
    private let rootReference: RuleLinkRootReference

    var itemControllable: any ItemControllable { itemController }

    @MainActor
    func setUp(rootManager: RootManager) {
        rootReference.rootManager = rootManager
    }

    @MainActor
    private var resolvedRootManager: RootManager {
        guard let rootManager = rootReference.rootManager else {
            preconditionFailure("Rule LinkController requires setUp(rootManager:) to be called before use.")
        }
        return rootManager
    }
}

extension LinkController: LinkControllable {
    @MainActor
    func handleTextLink(
        url: URL,
        in text: String,
        shareResult: ShareValueResult?,
        toggler: ((UUID, NetworkModules) async -> Void)?,
        editAction: ((ItemRowModel) -> Bool)?
    ) -> String {
        let module = url.moduleIdentifier
        if module != .rule,
           let controller = resolvedRootManager.rootModel(for: module)?.linkControllable {
            return controller.handleTextLink(
                url: url,
                in: text,
                shareResult: shareResult,
                toggler: toggler,
                editAction: editAction
            )
        }
        guard let itemId = url.itemId else { return text }
        guard let broken = brokenTextLinkToggle(
            url: url,
            itemId: itemId,
            entryId: url.childId,
            in: text
        ) else {
            return toggleTextLink(
                linkNumber: url.linkNumber,
                itemId: itemId,
                entryId: url.childId,
                command: url.commandKey,
                in: text,
                shareResult: shareResult,
                toggler: toggler,
                editAction: editAction
            )
        }
        return broken
    }

    @MainActor
    func toggleTextLink(
        linkNumber: Int,
        itemId: UUID,
        entryId: UUID?,
        command: String?,
        in text: String,
        shareResult: ShareValueResult?,
        toggler: ((UUID, NetworkModules) async -> Void)?,
        editAction: ((ItemRowModel) -> Bool)?
    ) -> String {
        if let command {
            if command == LinkType.remove.rawValue {
                let url = generateLink(
                    linkNumber: linkNumber - LinkType.remove.linkNumberAddition,
                    itemId: itemId,
                    entryId: entryId
                )
                return text.toggleLink(
                    url: url,
                    with: name(for: itemId, entryId: entryId),
                    remove: true
                )
            }
            Task {
                if command != LinkType.share.rawValue {
                    await toggler?(itemId, .rule)
                }
            }
            return text
        }

        let item = itemController.itemOrEmpty(for: itemId)
        let showAction = toggler != nil && entryId != nil
            ? specialLink(linkType: .show, linkNumber: linkNumber, itemId: itemId, entryId: entryId)
            : ""
        let removeAction = autoToggleAndRemoveAction(linkNumber: linkNumber, itemId: itemId, entryId: entryId, toggler: toggler, editAction: editAction)
        let detail = if let entryId {
            item[entryId].content
        } else {
            formatInlineDescription(description: item.description, entryCount: item.entries.count)
        }
        let expanded = "\(showAction) \(detail)\(removeAction)"
        return text.toggleLink(
            url: generateLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId),
            with: expanded
        )
    }

    @MainActor
    func repairLinks(_ links: [LinkReplaceModel], in content: String) -> String {
        links.reduce(content) { current, link in
            if link.module == .rule {
                return repairLink(link, for: current, for: [.all])
            }
            return resolvedRootManager.rootModel(for: link.module)?.linkControllable
                .repairLink(link, for: current, for: [.all]) ?? current
        }
    }

    @MainActor
    func validateLinks(on itemId: UUID) {
        guard let inspected = itemController.itemSync(for: itemId),
              inspected.displayState != DisplayStateMask.totalHidden.rawValue,
              let replacement = itemController.copy(of: itemId) else { return }

        replacement.description = repairLinks(
            LinkReplaceController.links(for: inspected.description),
            in: inspected.description
        )
        for entry in inspected.entries {
            var updated = entry
            updated.content = repairLinks(entry.links(for: entry.content), in: entry.content)
            if updated != entry {
                replacement[entry.id] = updated
            }
        }
        if !replacement.isSame(inspected) {
            Logger.linkController.info("Rule links repaired for \(replacement.name, privacy: .private)")
            itemController.replace(model: replacement, isInsert: false)
        }
        resetLinkRegister(replacement)
    }

    @MainActor
    func link(for name: String, entryName: String?) -> String? {
        guard let itemId = itemController.itemDataModel.items.first(where: {
            itemController.nameSync(itemId: $0) == name
        }) else { return nil }
        let item = itemController.itemOrEmpty(for: itemId)
        guard let entryName else { return item.url(linkNumber: 0) }
        let matchingEntries = item.entries.filter { $0.name == entryName }
        guard matchingEntries.count == 1, let entry = matchingEntries.first else { return nil }
        return item.url(linkNumber: 0, entryId: entry.id)
    }

    @MainActor
    func collectLinks(of module: NetworkModules, from itemId: UUID) -> [UUID] {
        guard let item = itemController.itemSync(for: itemId) else { return [] }
        let descriptionLinks = LinkReplaceController.links(for: item.description)
        let entryLinks = item.entries.flatMap { entry in
            entry.links(for: entry.content)
        }
        return Array(Set((descriptionLinks + entryLinks)
            .filter { $0.module == module }
            .map(\.itemId)))
    }
}
