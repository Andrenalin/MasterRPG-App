// @copyright André Trettin

import Foundation
import Network
import os.log
import CoreRPG

protocol ConnectionControllable {
    func startConnection()
    func cancel()

    func request(type: GameMessageType, with content: MessageMapper?)
    func response(type: GameMessageType, with content: MessageMapper?)
}

protocol ConnectionControllerDelegate: Sendable & AnyObject {
    func received(data: Data?, for id: ConnectionController.ID) async
    func failed(with error: String?, for id: ConnectionController.ID) async
    func lostConnection(for id: ConnectionController.ID) async
    func readyConnection(for id: ConnectionController.ID) async
}

final class ConnectionController: Sendable, Identifiable {
    let id: UUID
    private let connection: NWConnection
    private unowned let delegate: ConnectionControllerDelegate?
    
    init(id: UUID, endpoint: NWEndpoint, delegate: ConnectionControllerDelegate) {
        self.id = id
        self.connection = NWConnection.connection(endpoint: endpoint)
        self.delegate = delegate
        let connectionContext = connection.debugDescription
        Logger.connectionController.debug("Connection: \(id.uuidString, privacy: .public) Init \(connectionContext, privacy: .public)")
    }
    
    init(id: UUID, connection: NWConnection, delegate: ConnectionControllerDelegate) {
        self.id = id
        self.connection = connection
        self.delegate = delegate
        let connectionContext = connection.debugDescription
        Logger.connectionController.debug("Connection: \(id.uuidString, privacy: .public) Init \(connectionContext, privacy: .public)")
    }
}

extension ConnectionController: ConnectionControllable {
    
    func sendResponse(data: MessageMapper?) {
        let uuid = id.uuidString
        Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Send data")
        response(type: .gameData, with: data)
    }

    func request(with content: MessageMapper?) {
        let uuid = id.uuidString
        Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Send request")
        request(type: .gameData, with: content)
    }

    // Handle starting the peer-to-peer connection for both inbound and outbound connections.
    func startConnection() {
        let connectionContext = connection.debugDescription
        let uuid = id.uuidString
        Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Start \(connectionContext, privacy: .public)")

        connection.stateUpdateHandler = { [self] newState in
            Task {
                await self.stateChanged(newState)
            }
        }

        // Start the connection establishment.
        connection.start(queue: .main)
    }
    
    // Handle the user exiting the game.
    func cancel() {
        connection.cancel()
    }

    // MARK: - Player requests
    func request(type: GameMessageType, with content: MessageMapper?) {
        let message = NWProtocolFramer.Message(gameMessageType: type)
        let context = NWConnection.ContentContext(identifier: "PlayerRequest", metadata: [message])

        connection.send(content: content?.encodeData(), contentContext: context, isComplete: true, completion: .idempotent)
    }

    // MARK: - Master response
    func response(type: GameMessageType, with content: MessageMapper?) {
        let message = NWProtocolFramer.Message(gameMessageType: type)
        let context = NWConnection.ContentContext(identifier: "MasterResponse", metadata: [message])

        connection.send(content: content?.encodeData(), contentContext: context, isComplete: true, completion: .idempotent)
    }
}

private extension ConnectionController {
    func stateChanged(_ newState: NWConnection.State) async {
        let connectionContext = connection.debugDescription
        let uuid = id.uuidString

        switch newState {
        case .ready:
            Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Established \(connectionContext, privacy: .public)")
            receiveNextMessage()
            await connectionReady()

        case let .failed(error):
            Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Failed \(connectionContext, privacy: .public) with error \(error.localizedDescription)")
            cancel()
            await connectionFailed(message: error.localizedDescription)

        case .cancelled:
            Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Cancelled \(connectionContext, privacy: .public)")
            cancel()
            await lostConnection()

        default:
            break
        }
    }
}

private extension ConnectionController {
    // Receive a message, deliver it to your delegate, and continue receiving more messages.
    func receiveNextMessage() {
//        guard let connection else {
//            delegate?.lostConnection()
//            return
//        }
        connection.receiveMessage { [self] content, context, _, error in
            Task {
                await process(content: content, context: context, error: error)
            }
        }
    }
    
    func process(content: Data?, context: NWConnection.ContentContext?, error: Error?) async {
        guard error == nil, let gameMessage = context?.protocolMetadata(definition: GameProtocol.definition) as? NWProtocolFramer.Message else {
            let uuid = id.uuidString
            Logger.connectionController.error("Connection: \(uuid, privacy: .public) Error \(error?.localizedDescription ?? "Message is not from MasterRPG")")
            cancel()
            await connectionFailed(message: error?.localizedDescription ?? "Message is not from MasterRPG")
            return
        }

        await receivedMessage(content: content, message: gameMessage)
        receiveNextMessage()
    }
}

// MARK: - ConnectionController Delegate calls

extension ConnectionController {
    func lostConnection() async {
        let uuid = id.uuidString
        Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Lost")
        await delegate?.lostConnection(for: id)
    }

    func connectionReady() async {
        let uuid = id.uuidString
        Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Ready")
        await delegate?.readyConnection(for: id)
    }

    func connectionFailed(message: String) async {
        let uuid = id.uuidString
        Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Failed \(message, privacy: .public)")
        await delegate?.failed(with: message, for: id)
    }

    func receivedMessage(content: Data?, message: NWProtocolFramer.Message) async {
        guard message.gameMessageType == .gameData else {
            let uuid = id.uuidString
            Logger.connectionController.error("Connection: \(uuid, privacy: .public) Invalid message")
            return
        }
        await delegate?.received(data: content, for: id)
    }
}

public extension Logger {
    static let connectionController = Logger(subsystem: subsystem, category: "ConnectionController")
}

