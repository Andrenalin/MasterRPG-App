// @copyright André Trettin

import Network
import os.log
import CoreRPG
import Foundation

protocol ListenerControllerDelegate: Sendable & AnyObject {
    func cancelled() async
    func newConnection(for nwConnection: NWConnection) async
}

protocol ListenerControllable: Sendable & AnyObject {
    func startListening()
    func stopListnening()
}

final class ListenerController: Sendable {
    // Set once in init, never reassigned. Swift runtime zeroes weak refs atomically — safe for concurrent reads.
    nonisolated(unsafe) private weak var delegate: (any ListenerControllerDelegate)?
    private let listener: NWListener?
    private let name: String
    private let serviceType: GameServiceType
    private let passcode: String = "GameMasterCode"

    init(player: String, delegate: ListenerControllerDelegate) {
        self.delegate = delegate
        name = player
        serviceType = .master
        self.listener = try? NWListener(using: NWParameters(passcode: passcode))
        Logger.listenerController.debug("Listener: Init Player \(player, privacy: .public)")
    }

    init(master: String, delegate: ListenerControllerDelegate) {
        self.delegate = delegate
        name = master
        serviceType = .player
        self.listener = try? NWListener(using: NWParameters(passcode: passcode))
        Logger.listenerController.debug("Listener: Init Master \(master, privacy: .public)")
    }

    init(proxy: String, delegate: ListenerControllerDelegate) {
        self.delegate = delegate
        name = proxy
        serviceType = .proxyServer
        // passcode = "\(Int.random(in: 0...9))\(Int.random(in: 0...9))\(Int.random(in: 0...9))\(Int.random(in: 0...9))"
        self.listener = try? NWListener(using: NWParameters(passcode: passcode))
        Logger.listenerController.debug("Listener: Init Proxy \(proxy, privacy: .public)")
    }

    deinit {
        let listenerName = name
        Logger.listenerController.debug("Listener: Deinit \(listenerName, privacy: .public)")
    }
}

extension ListenerController: ListenerControllable {
    func startListening() {
        let listenerName = name
        let serviceName = serviceType.serviceName
        
        guard let listener  else {
            Logger.networking.fault("Listener: \(listenerName, privacy: .public) and service: \(serviceName) failed to create listener")
            Task { @concurrent in
                await self.delegate?.cancelled()
            }
            return
        }

        // Set the service to advertise.
        listener.service = NWListener.Service(name: name, type: serviceType.serviceName)

        Logger.networking.debug("Listener: \(listenerName, privacy: .public) and service: \(serviceName) init")

        listener.stateUpdateHandler = { [weak self] newState in
            self?.handleState(newState)
        }

        listener.newConnectionHandler = { [weak self] newConnection in
            self?.handleNewConnection(for: newConnection)
        }

        // Start listening, and request updates on the main queue.
        listener.start(queue: .main)
    }
    
    func stopListnening() {
        listener?.stateUpdateHandler = nil
        listener?.cancel()
    }
}

private extension ListenerController {
    func handleNewConnection(for newConnection: NWConnection) {
        Task { @concurrent in
            await self.delegate?.newConnection(for: newConnection)
        }
    }
    func handleState(_ state: NWListener.State) {
        let listenerName = name
        let serviceName = serviceType.serviceName

        switch state {
        case .ready:
            let port = "\(listener?.port ?? 0)"
            Logger.listenerController.debug("Listener: \(listenerName) and service: \(serviceName) ready on \(port, privacy: .public)")

        case let .failed(error):
            Logger.listenerController.error("Listener: \(listenerName) and service: \(serviceName) failed with \(error.localizedDescription, privacy: .public)")
            listener?.cancel()

        case .cancelled:
            Task { @concurrent in
                await self.delegate?.cancelled()
            }
        default:
            break
        }
    }
}

public extension Logger {
    static let listenerController = Logger(subsystem: subsystem, category: "ListenerController")
}
