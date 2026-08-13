// @copyright André Trettin

import Foundation
import Network
import os.log
import CoreRPG

protocol ConnectionControllable: Sendable {
    var id: UUID { get }

    func startConnection() async
    func cancel() async

    func request(type: GameMessageType, with content: MessageMapper?) async
    func response(type: GameMessageType, with content: MessageMapper?) async
    func request(type: GameMessageType, encodedContent: Data?) async
    func response(type: GameMessageType, encodedContent: Data?) async
}

protocol ConnectionControllerDelegate: Sendable & AnyObject {
    func received(data: Data?, for id: ConnectionController.ID) async
    func failed(with error: String?, for id: ConnectionController.ID) async
    func lostConnection(for id: ConnectionController.ID) async
    func readyConnection(for id: ConnectionController.ID) async
}

actor ConnectionController: Identifiable {
    nonisolated let id: UUID
    private let connection: NWConnection
    // NWConnection needs a dispatch queue; callbacks hop from it into the actor.
    private let queue = DispatchQueue(label: "de.andretrettin.MasterRPG.ConnectionController")
    private weak var delegate: (any ConnectionControllerDelegate)?
    private var receiveTask: Task<Void, Never>?

    init(id: UUID, endpoint: NWEndpoint, passcode: String, delegate: ConnectionControllerDelegate) {
        self.id = id
        self.connection = NWConnection.connection(endpoint: endpoint, passcode: passcode)
        self.delegate = delegate
        Logger.connectionController.debug("Connection: \(id.uuidString, privacy: .public) Init endpoint")
    }

    init(id: UUID, connection: NWConnection, delegate: ConnectionControllerDelegate) {
        self.id = id
        self.connection = connection
        self.delegate = delegate
        Logger.connectionController.debug("Connection: \(id.uuidString, privacy: .public) Init connection")
    }

    deinit {
        // Owners may drop connections without an explicit cancel() (e.g. resetConntections).
        receiveTask?.cancel()
        connection.cancel()
    }
}

extension ConnectionController: ConnectionControllable {

    func sendResponse(data: MessageMapper?) {
        response(type: .gameData, with: data)
    }

    func request(with content: MessageMapper?) {
        request(type: .gameData, with: content)
    }

    func startConnection() {
        let uuid = id.uuidString
        Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Start")

        connection.stateUpdateHandler = { [weak self] newState in
            Task {
                await self?.stateChanged(newState)
            }
        }
        connection.start(queue: queue)
    }

    func cancel() {
        receiveTask?.cancel()
        receiveTask = nil
        connection.cancel()
    }

    func request(type: GameMessageType, with content: MessageMapper?) {
        request(type: type, encodedContent: content?.encodeData())
    }

    func response(type: GameMessageType, with content: MessageMapper?) {
        response(type: type, encodedContent: content?.encodeData())
    }

    func request(type: GameMessageType, encodedContent: Data?) {
        let uuid = id.uuidString
        Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Send request")
        let message = NWProtocolFramer.Message(gameMessageType: type)
        let context = NWConnection.ContentContext(identifier: "PlayerRequest", metadata: [message])
        connection.send(content: encodedContent, contentContext: context, isComplete: true, completion: .idempotent)
    }

    func response(type: GameMessageType, encodedContent: Data?) {
        let uuid = id.uuidString
        Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Send response")
        let message = NWProtocolFramer.Message(gameMessageType: type)
        let context = NWConnection.ContentContext(identifier: "MasterResponse", metadata: [message])
        connection.send(content: encodedContent, contentContext: context, isComplete: true, completion: .idempotent)
    }
}

#if DEBUG
/// Test-only spy that records the already encoded payload handed to a connection.
actor ConnectionControllableSpyingStub: ConnectionControllable {
    nonisolated let id: UUID

    private(set) var calledStartConnection = 0
    private(set) var calledCancel = 0
    private(set) var requestTypes: [GameMessageType] = []
    private(set) var responseTypes: [GameMessageType] = []
    private(set) var requestEncodedContents: [Data?] = []
    private(set) var responseEncodedContents: [Data?] = []

    init(id: UUID = UUID()) {
        self.id = id
    }

    func startConnection() {
        calledStartConnection += 1
    }

    func cancel() {
        calledCancel += 1
    }

    func request(type: GameMessageType, with content: MessageMapper?) {
        request(type: type, encodedContent: content?.encodeData())
    }

    func response(type: GameMessageType, with content: MessageMapper?) {
        response(type: type, encodedContent: content?.encodeData())
    }

    func request(type: GameMessageType, encodedContent: Data?) {
        requestTypes.append(type)
        requestEncodedContents.append(encodedContent)
    }

    func response(type: GameMessageType, encodedContent: Data?) {
        responseTypes.append(type)
        responseEncodedContents.append(encodedContent)
    }
}
#endif

private extension ConnectionController {
    func stateChanged(_ newState: NWConnection.State) async {
        let uuid = id.uuidString

        switch newState {
        case .ready:
            Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Ready")
            startReceiveLoop()
            await connectionReady()

        case let .failed(error):
            Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Failed \(error.localizedDescription, privacy: .public)")
            cancel()
            await connectionFailed(message: error.localizedDescription)

        case .cancelled:
            Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Cancelled")
            await lostConnection()

        default:
            break
        }
    }

    func startReceiveLoop() {
        guard receiveTask == nil else { return }
        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop()
        }
    }

    func receiveLoop() async {
        while !Task.isCancelled {
            let shouldContinue = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                connection.receiveMessage { [weak self] content, context, _, error in
                    guard let self else {
                        continuation.resume(returning: false)
                        return
                    }
                    Task {
                        await self.process(content: content, context: context, error: error)
                        continuation.resume(returning: error == nil)
                    }
                }
            }
            if !shouldContinue { break }
        }
    }

    func process(content: Data?, context: NWConnection.ContentContext?, error: Error?) async {
        guard error == nil,
              let gameMessage = context?.protocolMetadata(definition: GameProtocol.definition) as? NWProtocolFramer.Message
        else {
            let uuid = id.uuidString
            Logger.connectionController.error("Connection: \(uuid, privacy: .public) Error \(error?.localizedDescription ?? "Message is not from MasterRPG", privacy: .public)")
            if error != nil {
                cancel()
                await connectionFailed(message: error?.localizedDescription ?? "Message is not from MasterRPG")
            }
            return
        }
        await receivedMessage(content: content, message: gameMessage)
    }
}

extension ConnectionController {
    func lostConnection() async {
        let uuid = id.uuidString
        Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Lost")
        await delegate?.lostConnection(for: id)
    }

    func connectionReady() async {
        let uuid = id.uuidString
        Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Established")
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
            Logger.connectionController.error("Connection: \(uuid, privacy: .public) Invalid message type")
            return
        }
        await delegate?.received(data: content, for: id)
    }
}

public extension Logger {
    static let connectionController = Logger(subsystem: subsystem, category: "ConnectionController")
}
