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

@MainActor
final class NetworkProxyControllerModel {
    init(name: String) {
        self.name = name
    }

    let name: String

    var masterDelegate: (any MasterNetworkProxyControllerDelegate)? { _masterDelegate }
    var playerDelegate: (any PlayerNetworkProxyControllerDelegate)? { _playerDelegate }

    private(set) var masterNetworkController: (any MasterNetworkControllable)?
    private(set) var playerNetworkController: (any PlayerNetworkControllable)?

    func setControllers(master: any MasterNetworkControllable, player: any PlayerNetworkControllable) {
        masterNetworkController = master
        playerNetworkController = player
    }

    func setMaster(delegate: any MasterNetworkProxyControllerDelegate) {
        _masterDelegate = delegate
    }

    func setPlayer(delegate: any PlayerNetworkProxyControllerDelegate) {
        _playerDelegate = delegate
    }

    private weak var _masterDelegate: (any MasterNetworkProxyControllerDelegate)?
    private weak var _playerDelegate: (any PlayerNetworkProxyControllerDelegate)?
}
