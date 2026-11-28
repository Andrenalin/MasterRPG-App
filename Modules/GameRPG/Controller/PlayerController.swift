// @copyright André Trettin

import CoreRPG
import Foundation
import os.log

@MainActor
final class PlayerController {
    // Strong on purpose: an intentional, temporary cycle GameRoot → GameModel →
    // PlayerController → GameRoot that stopGame() breaks by dropping the controllers.
    // `unowned` crashed here when in-flight controller tasks outlived
    // stopGame()/teardown. A strong reference keeps GameRoot alive until the
    // last task finishes.
    let root: GameRoot
    let gameModel: PlayerControllerModel
    let proxyMasterController: MasterController?
    let messagePipeline = GameMessagePipeline()

    init(root: GameRoot, asGameMaster: Bool) {
        self.root = root
        self.gameModel = PlayerControllerModel()
        self.gameModel.asGameMaster = asGameMaster

        if asGameMaster {
            proxyMasterController = nil
            root.networkStore.setupLocal()
            // A co-located local player never goes through the network
            // `ready()`/`lostConnection()` delegate lifecycle — `setupLocal()`
            // wires it directly, and `GameNetworkController` explicitly skips
            // calling `ready()` for it (`guard !model.hasLocalPlayer`). Left
            // at its default, `lostMaster` (and the `canSendCharacter` gate
            // derived from it) would stay permanently `true`/`false` for the
            // entire session — currently masked only by defensive guards at
            // every call site that reads it. See CODE_AUDIT_Reconnect §5.2.
            gameModel.reset(lostMaster: false)
        } else {
            proxyMasterController = MasterController(root: root, asProxy: true)
        }
        root.networkStore.model.setPlayerDelegate(self)
        root.networkProxyStore.model.setProxyPlayerDelegate(self)
        installMapPhotoActions()
        installCharacterEditAnnouncement()
        Logger.networking.debug("PlayerController: Init")
    }

    deinit {
        Logger.networking.debug("PlayerController: Deinit")
    }
}

// Empty conformance declaration kept in the same file as the class itself — Swift requires a
// class's `Sendable` conformance (inherited here via `PlayerNetworkStoreDelegate: Sendable`) to
// be declared alongside the class, even though the actual protocol requirements are implemented
// in `PlayerController+NetworkStoreDelegate.swift`.
// DO NOT MOVE OR REMOVE THIS IN A CODE AUDIT: moving it into the other file compiles but warns
// ("Conformance to 'Sendable' must occur in the same source file", an error in a future Swift
// language mode). It looks redundant and is not. (CODE_AUDIT_28 §3.5 got this wrong once.)
extension PlayerController: PlayerNetworkStoreDelegate {}
