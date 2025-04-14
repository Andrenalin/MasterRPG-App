// @copyright André Trettin

import Foundation
import Network
import os.log

protocol MasterNetworkControllerDelegate: Sendable & AnyObject {
    func masterLostPlayer(with connectionId: ConnectionController.ID) async
    func masterReady(for connectionId: ConnectionController.ID) async
    func masterReceived(data: Data?, for connectionId: ConnectionController.ID, fileJournal: Bool) async
}

protocol MasterNetworkControllable: Sendable & AnyObject {
    var networkModel: MasterNetworkNodel { get }

    @MainActor func startStreaming()
    @MainActor func stopStreaming()
    @MainActor func toggleStreaming()
    @MainActor func startProxyStreaming()

    func sendResponse(data: MessageMapper?, id: ConnectionController.ID) async
    func sendResponse(data: MessageMapper?) async
    func sendResponse(data: MessageMapper?, except: ConnectionController.ID) async
}

@MainActor @Observable
final class MasterNetworkNodel: @unchecked Sendable {
    init(name: String = "Master Device") {
        self.name = name
    }
    
    var name: String
    var connections: [ConnectionController] = []
    var isStreaming: Bool = false
    
    @ObservationIgnored var browserController: BrowserController? = nil
    var browserConnections: [NWEndpoint] = []
    @ObservationIgnored var listener: ListenerControllable? = nil
    
    func removeConnection(id: ConnectionController.ID) -> Bool {
        guard let index = connections.firstIndex(where: { $0.id == id }) else { return false }
        connections.remove(at: index)
        return true
    }
    
    func reset(isStreaming: Bool) {
        self.isStreaming = isStreaming
    }
}
