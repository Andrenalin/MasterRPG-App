// @copyright André Trettin

import CoreRPG
import Foundation
import Network
import os.log

protocol MasterNetworkControllerDelegate: Sendable & AnyObject {
    func masterLostPlayer(with connectionId: ConnectionController.ID) async
    func masterReady(for connectionId: ConnectionController.ID) async
    func masterReceived(data: Data?, for connectionId: ConnectionController.ID, fileJournal: Bool) async
}

protocol MasterNetworkControllable: Sendable & AnyObject {
    var networkModel: MasterNetworkModel { get }

    @MainActor func startStreaming(passcode: String)
    @MainActor func stopStreaming()
    @MainActor func toggleStreaming(passcode: String)
    @MainActor func startProxyStreaming(passcode: String)

    /// Returns whether a connection with that id exists and the data was handed
    /// to it — false means the id is unknown here (e.g. a SharePlay participant)
    /// and the caller must deliver another way.
    @discardableResult
    func sendResponse(data: MessageMapper?, id: ConnectionController.ID) async -> Bool
    func sendResponse(data: MessageMapper?) async
    func sendResponse(data: MessageMapper?, except: ConnectionController.ID) async
}

@MainActor @Observable
final class MasterNetworkModel {
    init(name: String = "Master Device") {
        self.name = name
    }
    
    var name: String
    var supporterTier: SupporterTier = .none
    var connections: [any ConnectionControllable] = []
    var isStreaming: Bool = false

    /// The join code this session's listener was started with. Captured once
    /// at `startStreaming(passcode:)`/`startProxyStreaming(passcode:)` and
    /// reused for every reconnect dial-out to a lost player for the lifetime
    /// of the session, even if the user changes their stored code afterwards.
    @ObservationIgnored var passcode: String = ""

    @ObservationIgnored var browserManager: BrowserManager? = nil
    @ObservationIgnored var observeConnectionsTask: Task<Void, Never>? = nil
    @ObservationIgnored var connectionStartTasks: [ConnectionController.ID: Task<Void, Never>] = [:]
    /// Bumped by every connection reset, so an admission that suspended across the reset can
    /// tell it is stale. See CODE_AUDIT_16 §3.3.
    @ObservationIgnored var connectionGeneration = 0
    var browserConnections: [NWEndpoint] = []
    @ObservationIgnored var listener: (any ListenerManaging)? = nil
    
    func removeConnection(id: ConnectionController.ID) -> Bool {
        guard let index = connections.firstIndex(where: { $0.id == id }) else { return false }
        connections.remove(at: index)
        return true
    }
    
    func reset(isStreaming: Bool) {
        self.isStreaming = isStreaming
    }
}
