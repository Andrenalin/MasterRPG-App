// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import SwiftUI

protocol MasterNetworkProxyControllerDelegate: Sendable & AnyObject {
    func readyProxy(for connectionId: ConnectionController.ID) async
    func receivedServerProxy(_ model: GameNetworkModel) async
}

protocol PlayerNetworkProxyControllerDelegate: Sendable & AnyObject {
    func lostProxyConnection() async
    func readyProxy() async
    func receivedProxy(_ model: GameNetworkModel) async
}

actor NetworkProxyControllerModel: Sendable {
    init(name: String) {
        self.name = name
    }
    
    let name: String
    
    var masterDelegate: MasterNetworkProxyControllerDelegate? {
        _masterDelegate
    }
    var playerDelegate: PlayerNetworkProxyControllerDelegate? {
        _playerDelegate
    }
    
    private(set) var masterNetworkController: (any MasterNetworkControllable)?
    private(set) var playerNetworkController: (any PlayerNetworkControllable)?

    func setControllers(master: MasterNetworkControllable, player: PlayerNetworkControllable) async {
        masterNetworkController = master
        playerNetworkController = player
    }
    
    func setMaster(delegate: MasterNetworkProxyControllerDelegate) async {
        _masterDelegate = delegate
    }
    
    func setPlayer(delegate: PlayerNetworkProxyControllerDelegate) async {
        _playerDelegate = delegate
    }
    
    private weak var _masterDelegate: MasterNetworkProxyControllerDelegate?
    private weak var _playerDelegate: PlayerNetworkProxyControllerDelegate?
}
