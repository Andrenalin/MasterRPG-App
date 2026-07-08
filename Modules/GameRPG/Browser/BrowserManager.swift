import CoreRPG
import Network
import OSLog
import SwiftUI

/// Events that occur during client-server life cycle and connection state changes.
public enum NetworkEvent: Sendable {
    case browserRunning
    case connecting
    case browserStopped(NWError?)
    case endpointsUpdated([Bonjour.Endpoint])
}

/// UI-friendly connection states mapped from `NetworkEvent`.
public enum NetworkState: String, Sendable {
    case stopped
    case tlsFailed
    case connected
    case connecting
    case waitingForConnection
    case cancelled
}


@Observable @MainActor
final class BrowserManager {

    let serviceType: GameServiceType

    private(set) var connectionState: NetworkState = .cancelled
    private(set) var errorMessage: String?
    private(set) var games: [BrowserGameModel] = []
    private(set) var removed: [BrowserGameModel] = []

    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var networkTask: Task<Void, Never>?

    init(serviceType: GameServiceType = .player) {
        self.serviceType = serviceType
    }

    isolated deinit {
        cancelTasks()
    }

    var isBrowsing: Bool {
        connectionState == .waitingForConnection || connectionState == .connecting
    }

    var connectionMode: BrowserConnectionMode { serviceType.connectionMode }

    func start() {
        guard !isBrowsing else { return }
        cancelTasks()
        connectionState = .connecting
        games = []
        removed = []

        let controller = BrowserClientController(serviceType: serviceType)

        monitorTask = Task { @MainActor [weak self] in
            for await event in controller.networkUpdateEvents {
                self?.handleStateEvent(event)
            }
        }

        networkTask = Task { [weak self] in
            do {
                try await controller.startBrowser()
            } catch is CancellationError {
                await MainActor.run { self?.connectionState = .cancelled }
            } catch {
                Logger.browserController.log("Browser error: \(error.localizedDescription)")
                await MainActor.run { self?.connectionState = .stopped }
            }
        }
    }

    func stop() {
        cancelTasks()
        connectionState = .stopped
        games = []
        removed = []
    }

    func nwEndpoint(for game: BrowserGameModel) -> NWEndpoint {
        .service(name: game.endpointName, type: serviceType.serviceName, domain: "local.", interface: nil)
    }

    private func cancelTasks() {
        networkTask?.cancel()
        networkTask = nil
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func handleStateEvent(_ event: NetworkEvent) {
        switch event {
        case .browserRunning:
            connectionState = .waitingForConnection
        case .connecting:
            connectionState = .connecting
        case .browserStopped(let error):
            Logger.browserController.log("Browser stopped: \(String(describing: error))")
            connectionState = .stopped
        case .endpointsUpdated(let endpoints):
            updateGames(from: endpoints)
        }
    }

    private func updateGames(from endpoints: [Bonjour.Endpoint]) {
        let newNames = Set(endpoints.map { $0.name })
        removed = games.filter { !newNames.contains($0.endpointName) }
        games.removeAll { !newNames.contains($0.endpointName) }
        let existing = Set(games.map { $0.endpointName })
        for endpoint in endpoints where !existing.contains(endpoint.name) {
            games.append(BrowserGameModel(id: UUID(), endpointName: endpoint.name, connectionMode: serviceType.connectionMode))
            Logger.browserController.log("Found endpoint: \(endpoint.name)")
        }
    }
}

@Observable @MainActor
final class BrowserGameModel: Identifiable {
    let id: UUID
    let endpointName: String
    let connectionMode: BrowserConnectionMode

    var deviceName: String {
        String(endpointName.prefix(while: { $0 != "." }))
    }

    init(id: UUID, endpointName: String, connectionMode: BrowserConnectionMode) {
        self.id = id
        self.endpointName = endpointName
        self.connectionMode = connectionMode
    }
}

actor BrowserClientController {
    private let serviceType: GameServiceType
    let networkUpdateEvents: AsyncStream<NetworkEvent>
    private let networkUpdateContinuation: AsyncStream<NetworkEvent>.Continuation

    init(serviceType: GameServiceType) {
        self.serviceType = serviceType
        (self.networkUpdateEvents, self.networkUpdateContinuation) = AsyncStream.makeStream(of: NetworkEvent.self)
    }

    func startBrowser() async throws {
        defer {
            networkUpdateContinuation.finish()
        }

        try await NetworkBrowser(
            for: .bonjour(serviceType.serviceName, includeTxtRecord: true),
            using: .tls)
        .onStateUpdate { _, state in
            self.handleBrowserStateUpdates(state)
        }
        .run { endpoints in
            self.networkUpdateContinuation.yield(.endpointsUpdated(endpoints))
        }
    }

    private func handleBrowserStateUpdates(_ state: NetworkBrowser<Bonjour>.State) {
        switch state {
        case .ready:
            networkUpdateContinuation.yield(.browserRunning)
        case .failed(let nWError):
            networkUpdateContinuation.yield(.browserStopped(nWError))
        case .cancelled:
            networkUpdateContinuation.yield(.browserStopped(nil))
        default: break
        }
    }
}

extension Logger {
    static let browserController = Logger(subsystem: subsystem, category: "BrowserController")
}
