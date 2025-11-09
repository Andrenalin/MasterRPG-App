// @copyright André Trettin

import AndrenalinKit
import Foundation
import SwiftUI

public struct LinkController: Sendable {
    init(itemController: ItemController, audioController: AudioController, gameController: GameController) {
        self.itemController = itemController
        self.audioController = audioController
        self.gameController = gameController
    }
    let itemController: ItemController
    let audioController: AudioController
    let gameController: GameController
    
    public var itemControllable: any ItemControllable {
        itemController
    }
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
                Task { @MainActor in
                    await toggler?(itemId, itemControllable.itemDataModel.networkModule)
                }
                return text
            }
            if command == LinkType.play.rawValue {
                let playUrl = specialLink(linkType: .play, linkNumber: linkNumber, itemId: itemId, entryId: entryId)

                if let shareResult, shareResult.showGame {
                    if gameController.allPlayersReported(for: itemId) {
                        let isPlaying = audioController.model.isPlaying
                        shareResult.networkActions?.game(gameController.requestPlay(id: itemId), .playAudio)
                        return text.toggleLink(url: playUrl, with: "\(!isPlaying ? "playing" : "pause")", replace: true)
                    } else {
                        Task { @MainActor in
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
            // send
            Task { @MainActor in
                await shareResult?.networkActions?.shareId(gameController.share(id: itemId))
            }
            return text
        } else {
            if let toggler, entryId == nil, editAction == nil {
                Task { @MainActor in
                    await toggler(itemId, itemControllable.itemDataModel.networkModule)
                }
            }
            let item = itemController.itemOrEmpty(for: itemId)
            let sendAction = ((shareResult?.showGame ?? false) && shareResult?.networkActions != nil) ? "\(specialLink(linkType: .share, linkNumber: linkNumber, itemId: itemId, entryId: entryId)) " : ""
            let showAction = toggler != nil ? "\(specialLink(linkType: .show, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let editLine = editAction?(ItemRowModel(itemId: itemId, entryId: entryId, typeId: itemController.itemDataModel.networkModule)) ?? false
            let removeAction = editLine ? " \(specialLink(linkType: .remove, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let result = "\(sendAction)\(showAction)\(specialLink(linkType: .play, linkNumber: linkNumber, itemId: itemId, entryId: entryId)) \(item.description)\(removeAction)"
            let url = generateLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId)
            return text.toggleLink(url: url, with: result)
        }
    }
    
    @MainActor
    public func generateLink(linkNumber: Int, itemId: UUID, entryId: UUID?) -> String {
        guard let entryId else { return itemControllable.itemOrEmpty(for: itemId).url(linkNumber: linkNumber) }
        return itemControllable.itemOrEmpty(for: entryId).url(linkNumber: linkNumber)
    }
}
