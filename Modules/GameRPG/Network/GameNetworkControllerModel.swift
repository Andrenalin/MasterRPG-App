// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import SwiftUI

// MARK: - Direct-mode delegate protocols

protocol MasterNetworkStoreDelegate: Sendable & AnyObject {
    func ready(for connectionId: ConnectionController.ID) async
    func received(_ model: GameNetworkModel, connectionId: ConnectionController.ID?) async
    func receivedFile(_ model: GameNetworkModel) async
    func lostPlayer(for connectionId: ConnectionController.ID) async
}

protocol PlayerNetworkStoreDelegate: Sendable & AnyObject {
    func lostConnection() async
    func ready() async
    func received(_ model: GameNetworkModel) async
    func receivedFile(_ model: GameNetworkModel) async
    func receivedSharePlay(_ model: GameNetworkModel, participantId: UUID) async
    func receivedSharePlayFile(_ model: GameNetworkModel) async
    func sharePlayFileLoadFailed(_ model: GameNetworkModel) async
}

extension PlayerNetworkStoreDelegate {
    func receivedSharePlay(_ model: GameNetworkModel, participantId: UUID) async {
        await received(model)
    }

    func receivedSharePlayFile(_ model: GameNetworkModel) async {
        await receivedFile(model)
    }

    func sharePlayFileLoadFailed(_ model: GameNetworkModel) async {
        await receivedSharePlayFile(model)
    }
}

// MARK: - Proxy-mode delegate protocols

protocol MasterNetworkProxyControllerDelegate: Sendable & AnyObject {
    func readyProxy(for connectionId: ConnectionController.ID) async
    func receivedServerProxy(_ model: GameNetworkModel) async
}

protocol PlayerNetworkProxyControllerDelegate: Sendable & AnyObject {
    func lostProxyConnection() async
    func readyProxy() async
    func receivedProxy(_ model: GameNetworkModel) async
}

// MARK: - Model

@MainActor
final class GameNetworkControllerModel {
    let name: String
    var isSetup: Bool = false
    var hasLocalPlayer = false

    private(set) var masterStore: (any MasterNetworkControllable)?
    private(set) var playerStore: (any PlayerNetworkControllable)?

    init(name: String) {
        self.name = name
    }

    func setControllers(master: any MasterNetworkControllable, player: any PlayerNetworkControllable) {
        masterStore = master
        playerStore = player
    }

    func didSetup() { isSetup = true }

    func setLocalPlayers(to hasPlayers: Bool) { hasLocalPlayer = hasPlayers }

    // MARK: Direct-mode delegates

    var masterDelegate: (any MasterNetworkStoreDelegate)? { _masterDelegate }
    var playerDelegate: (any PlayerNetworkStoreDelegate)? { _playerDelegate }

    func setMasterDelegate(_ delegate: any MasterNetworkStoreDelegate) { _masterDelegate = delegate }
    func setPlayerDelegate(_ delegate: any PlayerNetworkStoreDelegate) { _playerDelegate = delegate }

    private weak var _masterDelegate: (any MasterNetworkStoreDelegate)?
    private weak var _playerDelegate: (any PlayerNetworkStoreDelegate)?

    // MARK: Proxy-mode delegates

    var masterProxyDelegate: (any MasterNetworkProxyControllerDelegate)? { _masterProxyDelegate }
    var playerProxyDelegate: (any PlayerNetworkProxyControllerDelegate)? { _playerProxyDelegate }

    func setProxyMasterDelegate(_ delegate: any MasterNetworkProxyControllerDelegate) { _masterProxyDelegate = delegate }
    func setProxyPlayerDelegate(_ delegate: any PlayerNetworkProxyControllerDelegate) { _playerProxyDelegate = delegate }

    private weak var _masterProxyDelegate: (any MasterNetworkProxyControllerDelegate)?
    private weak var _playerProxyDelegate: (any PlayerNetworkProxyControllerDelegate)?
}
