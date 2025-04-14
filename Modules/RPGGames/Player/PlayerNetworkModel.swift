// @copyright André Trettin

import Foundation
import Network
import os.log

protocol PlayerNetworkControllerDelegate: Sendable & AnyObject {
    func playerLostMaster() async
    func playerReceived(data: Data?) async
    func playerReady() async
}

protocol PlayerNetworkControllable: Sendable & AnyObject {
    var networkModel: PlayerNetworkNodel { get }
    var browserController: BrowserController { get }

    @MainActor func toggleConnection(to model: BrowserDeviceModel) async
    @MainActor func stop() async

    func request(with content: MessageMapper?) async
}

@MainActor @Observable
final class PlayerNetworkNodel: @unchecked Sendable {
    init(name: String = "Player Device", model: PlayerBrowserModel? = nil, playerConnectionId: UUID? = nil, isConnected: Bool = false, connectionState: PlayerNetworkNodel.ConnectionState = .notReady) {
        self.name = name
        self.model = model
        self.playerConnectionId = playerConnectionId
        self.isConnected = isConnected
        self.connectionState = connectionState
    }
    
    var name: String
    var model: PlayerBrowserModel?
    var playerConnectionId: UUID?
    
    var isConnected: Bool
    
    enum ConnectionState {
        case notReady
        case ready
        case lost
    }
    var connectionState: ConnectionState
    
    func reset(isConnected: Bool) {
        self.isConnected = isConnected
    }
    
    func reset(state: ConnectionState) {
        self.connectionState = state
    }

    func reset(controller: ConnectionController) {
        self.connectionController = controller
    }

    func reset(listener: ListenerController?) {
        self.listener = listener
    }

    @ObservationIgnored var connectionController: ConnectionController? = nil
    @ObservationIgnored var listener: ListenerController? = nil
}

