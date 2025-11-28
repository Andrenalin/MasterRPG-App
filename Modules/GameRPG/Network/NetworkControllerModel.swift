// @copyright André Trettin

import AndrenalinKit
import Foundation
import os.log
import SwiftUI

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
}

@MainActor
final class NetworkControllerModel: Sendable {
    init(name: String) {
        self.name = name
    }
    
    let name: String
    var isSetup: Bool = false
    var hasLocalPlayer = false
    
    func didSetup() {
        isSetup = true
    }

    func setLocalPlayers(to hasPlayers: Bool) {
        hasLocalPlayer = hasPlayers
    }

    var masterDelegate: MasterNetworkStoreDelegate? {
        _masterDelegate
    }
    var playerDelegate: PlayerNetworkStoreDelegate? {
        _playerDelegate
    }
    
    private(set) var masterStore: (any MasterNetworkControllable)?
    private(set) var playerStore: (any PlayerNetworkControllable)?

    func setControllers(master: MasterNetworkControllable, player: PlayerNetworkControllable) {
        masterStore = master
        playerStore = player
    }
    
    func setMaster(delegate: MasterNetworkStoreDelegate) async {
        _masterDelegate = delegate
    }
    
    func setPlayer(delegate: PlayerNetworkStoreDelegate) async {
        _playerDelegate = delegate
    }
    
    private weak var _masterDelegate: MasterNetworkStoreDelegate?
    private weak var _playerDelegate: PlayerNetworkStoreDelegate?
}
