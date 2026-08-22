// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI
import os.log

struct LinkController: Sendable {
    let itemController: ItemController
    let audioController: AudioController
    let gameController: GameController

    public var itemControllable: any ItemControllable { itemController }
}

extension LinkController: LinkControllable {
    @MainActor
    public func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        if let command {
            if command == LinkType.remove.rawValue {
                let url = generateLink(linkNumber: linkNumber - LinkType.remove.linkNumberAddition, itemId: itemId, entryId: entryId)
                return text.toggleLink(url: url, with: name(for: itemId, entryId: entryId), remove: true)
            }
            if command == LinkType.show.rawValue {
                Task {
                    await toggler?(itemId, itemControllable.config.module)
                }
                return text
            }
            if command == LinkType.play.rawValue {
                let playUrl = specialLink(linkType: .play, linkNumber: linkNumber, itemId: itemId, entryId: entryId)

                if let shareResult, shareResult.showGame {
                    if gameController.allPlayersReported(for: itemId) {
                        let isPlaying = audioController.model.isPlaying
                        shareResult.networkActions?.game(gameController.requestPlay(id: itemId), .playAudio, nil)
                        return text.toggleLink(url: playUrl, with: "\(!isPlaying ? "playing" : "pause")", replace: true)
                    } else {
                        Task {
                            await shareResult.networkActions?.shareId(gameController.share(id: itemId))
                        }
                        return text.toggleLink(url: playUrl, with: "share audio", replace: true)
                    }
                } else {
                    let isPlaying = audioController.model.isPlaying && audioController.model.currentId == itemId
                    audioController.loadAndPlay(id: itemId)
                    return text.toggleLink(url: playUrl, with: "\(!isPlaying ? "playing" : "pause")", replace: true)
                }
            }
            guard command == LinkType.share.rawValue else { return text }
            Task {
                await shareResult?.networkActions?.shareId(gameController.share(id: itemId))
            }
            return text
        } else {
            if let toggler, entryId == nil, editAction == nil {
                Task {
                    await toggler(itemId, itemControllable.config.module)
                }
            }
            let item = itemController.itemOrEmpty(for: itemId)
            let sendAction = ((shareResult?.showGame ?? false) && shareResult?.networkActions != nil) ? "\(specialLink(linkType: .share, linkNumber: linkNumber, itemId: itemId, entryId: entryId)) " : ""
            let showAction = toggler != nil ? "\(specialLink(linkType: .show, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let editLine = editAction?(ItemRowModel(itemId: itemId, entryId: entryId, typeId: itemController.config.module)) ?? false
            let removeAction = editLine ? " \(specialLink(linkType: .remove, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let result = "\(sendAction)\(showAction)\(specialLink(linkType: .play, linkNumber: linkNumber, itemId: itemId, entryId: entryId)) \(item.description)\(removeAction)"
            let url = generateLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId)
            return text.toggleLink(url: url, with: result)
        }
    }

    @MainActor public func repairLinks(_ links: [LinkReplaceModel], in content: String) -> String {
        var result = content
        for link in links {
            result = repairLink(link, for: result, for: [.all])
        }
        return result
    }

    @MainActor public func validateLinks(on itemId: UUID) {
        guard let inspectedItem = itemController.itemSync(for: itemId), inspectedItem.displayState != 2, let replacedItem = itemController.copy(of: itemId) else { return }

        // Entries are single-child references (`ChildEntryModel`) with no free-text `content`
        // of their own to repair — only the item's own `description` can embed a link.
        replacedItem.description = repairLinks(LinkReplaceController.links(for: inspectedItem.description), in: inspectedItem.description)

        if !replacedItem.isSame(inspectedItem) {
            Logger.linkController.info("Audio: \(replacedItem.name, privacy: .public) will be replaced from repairing links.")
            itemController.replace(model: replacedItem, isInsert: false)
        }
        resetLinkRegister(replacedItem)
    }
}
