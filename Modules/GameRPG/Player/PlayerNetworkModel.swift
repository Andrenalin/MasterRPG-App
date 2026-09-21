// @copyright André Trettin

import CoreRPG
import Foundation
import Network
import os.log

protocol PlayerNetworkControllerDelegate: Sendable & AnyObject {
    func playerLostMaster() async
    func playerReceived(data: Data?) async
    func playerReady() async
}

protocol PlayerNetworkControllable: Sendable & AnyObject {
    var networkModel: PlayerNetworkModel { get }
    var browserManager: BrowserManager { get }

    /// Returns whether the join actually succeeded (the handshake completed
    /// and the passcode was accepted) — not merely whether the attempt was
    /// dialed. Callers must not treat a `true` return as immediate; it only
    /// resolves once the outcome is known.
    @MainActor func toggleConnection(to model: BrowserGameModel, passcode: String) async -> Bool
    @MainActor func stop() async

    func request(with content: MessageMapper?) async
}

@MainActor @Observable
final class PlayerNetworkModel {
    init(name: String = "Player Device", model: PlayerBrowserModel? = nil, playerConnectionId: UUID? = nil, isConnected: Bool = false, connectionState: PlayerNetworkModel.ConnectionState = .notReady) {
        self.name = name
        self.model = model
        self.playerConnectionId = playerConnectionId
        self.isConnected = isConnected
        self.connectionState = connectionState
    }
    
    var name: String
    var supporterTier: SupporterTier = .none
    var model: PlayerBrowserModel?
    var playerConnectionId: UUID?

    /// The join code entered to establish the current session. Captured once
    /// at `toggleConnection(to:passcode:)` and reused both for the outbound
    /// connection and any fallback listener this device opens afterwards, so
    /// automatic reconnects never need a fresh code entry.
    @ObservationIgnored var passcode: String = ""

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

    func reset(listener: (any ListenerManaging)?) {
        self.listener = listener
    }

    @ObservationIgnored var connectionController: ConnectionController? = nil
    @ObservationIgnored var listener: (any ListenerManaging)? = nil
    @ObservationIgnored var observeRemovalTask: Task<Void, Never>? = nil
    @ObservationIgnored var connectionStartTask: Task<Void, Never>? = nil
}
