import CoreRPG
import Network
import OSLog
import SwiftUI

/// Events that occur during client-server life cycle and connection state changes.
public enum NetworkEvent: Sendable {
    case browserRunning
    case connecting
    case browserWaiting(NWError)
    case browserStopped(NWError?)
    case endpointsUpdated([Bonjour.Endpoint])
}

/// UI-friendly connection states mapped from `NetworkEvent`.
public enum NetworkState: String, Sendable {
    case stopped
    case connecting
    case waitingForConnection
    case cancelled
}


@Observable @MainActor
final class BrowserManager {

    let serviceType: GameServiceType

    private(set) var connectionState: NetworkState = .cancelled
    /// Why the browser is not running, when it is not: the last failure or wait reason. Cleared
    /// as soon as browsing works again. See CODE_AUDIT_Join §8.2.
    private(set) var errorMessage: String?
    /// The system refused local-network access (the user denied the permission prompt). Browsing
    /// can never succeed until the setting changes, so the UI says so instead of "no games".
    private(set) var isLocalNetworkAccessDenied = false
    private(set) var games: [BrowserGameModel] = []
    private(set) var removed: [BrowserGameModel] = []

    @ObservationIgnored private var supervisorTask: Task<Void, Never>?
    @ObservationIgnored private var monitorTask: Task<Bool, Never>?
    @ObservationIgnored private var runGeneration = 0

    init(serviceType: GameServiceType = .player) {
        self.serviceType = serviceType
    }

    isolated deinit {
        cancelTasks()
    }

    var isBrowsing: Bool {
        connectionState == .waitingForConnection || connectionState == .connecting
    }

    /// Started and not explicitly stopped: the supervisor recreates the browser after a pause
    /// even while `isBrowsing` is briefly false. See CODE_AUDIT_18 §5.14.
    var isSupervising: Bool {
        supervisorTask != nil
    }

    var connectionMode: BrowserConnectionMode { serviceType.connectionMode }

    func start() {
        guard !isBrowsing else { return }
        cancelTasks()
        connectionState = .connecting
        games = []
        removed = []
        errorMessage = nil
        isLocalNetworkAccessDenied = false

        runGeneration += 1
        let generation = runGeneration
        // One supervising task owns every browser run for this start: a browser that fails or
        // ends without `stop()` is recreated after a backoff instead of leaving discovery dead
        // for the rest of the session. See CODE_AUDIT_Join §5.3.
        supervisorTask = Task { @MainActor [weak self] in
            await self?.supervise(generation: generation)
        }
    }

    func stop() {
        runGeneration += 1
        cancelTasks()
        connectionState = .stopped
        games = []
        removed = []
    }

    func nwEndpoint(for game: BrowserGameModel) -> NWEndpoint {
        .service(name: game.endpointName, type: serviceType.serviceName, domain: "local.", interface: nil)
    }

    private func cancelTasks() {
        supervisorTask?.cancel()
        supervisorTask = nil
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func supervise(generation: Int) async {
        var attempt = 0
        while !Task.isCancelled, runGeneration == generation {
            let controller = BrowserClientController(serviceType: serviceType)
            // Events of a superseded run are dropped: they must not overwrite the state of the
            // run that replaced it. See CODE_AUDIT_16 §3.8 and CODE_AUDIT_Join §3.2.
            let monitor = Task { @MainActor [weak self] in
                var sawReady = false
                for await event in controller.networkUpdateEvents {
                    guard let self, self.runGeneration == generation else { return sawReady }
                    if case .browserRunning = event { sawReady = true }
                    self.handleStateEvent(event)
                }
                return sawReady
            }
            monitorTask = monitor

            do {
                try await controller.startBrowser()
            } catch is CancellationError {
                monitor.cancel()
                return
            } catch {
                Logger.browserController.log("Browser error: \(error.localizedDescription)")
                guard runGeneration == generation else { return }
                record(failure: error)
            }
            let sawReady = await monitor.value
            guard !Task.isCancelled, runGeneration == generation else { return }

            if connectionState != .stopped { connectionState = .stopped }
            if sawReady { attempt = 0 }
            let delay = GameLimits.networkRestartDelay(forAttempt: attempt)
            attempt += 1
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, runGeneration == generation else { return }
            connectionState = .connecting
        }
    }

    private func handleStateEvent(_ event: NetworkEvent) {
        switch event {
        case .browserRunning:
            connectionState = .waitingForConnection
            errorMessage = nil
            isLocalNetworkAccessDenied = false
        case .connecting:
            connectionState = .connecting
        case .browserWaiting(let error):
            record(failure: error)
        case .browserStopped(let error):
            Logger.browserController.log("Browser stopped: \(String(describing: error))")
            connectionState = .stopped
            if let error { record(failure: error) }
        case .endpointsUpdated(let endpoints):
            updateGames(from: endpoints)
        }
    }

    private func record(failure error: any Error) {
        errorMessage = error.localizedDescription
        if let networkError = error as? NWError, case .dns(let code) = networkError, code == Self.policyDeniedCode {
            isLocalNetworkAccessDenied = true
        }
    }

    /// `kDNSServiceErr_PolicyDenied`: local-network access was denied by the user or policy.
    private static let policyDeniedCode: DNSServiceErrorType = -65570

    /// Returns and clears the removals accumulated since the last call. An update that removes
    /// nothing must not erase an earlier removal the consumer has not read yet.
    /// See CODE_AUDIT_16 §3.9.
    func takeRemoved() -> [BrowserGameModel] {
        defer { removed = [] }
        return removed
    }

    private func updateGames(from endpoints: [Bonjour.Endpoint]) {
        let newNames = Set(endpoints.map { $0.name })
        let newlyRemoved = games.filter { !newNames.contains($0.endpointName) }
        if !newlyRemoved.isEmpty {
            removed.append(contentsOf: newlyRemoved)
        }
        games.removeAll { !newNames.contains($0.endpointName) }
        let existing = Set(games.map { $0.endpointName })
        for endpoint in endpoints where !existing.contains(endpoint.name) {
            games.append(
                BrowserGameModel(
                    id: UUID(),
                    endpointName: endpoint.name,
                    connectionMode: serviceType.connectionMode,
                    supporterTier: Self.supporterTier(from: endpoint.txtRecord),
                    sessionId: endpoint.txtRecord[NWTXTRecord.sessionKey]
                )
            )
            Logger.browserController.log("Found endpoint: \(endpoint.name)")
        }
    }

    private static func supporterTier(from txtRecord: NWTXTRecord) -> SupporterTier {
        guard let rawString = txtRecord[NWTXTRecord.supporterTierKey], let rawValue = Int(rawString) else {
            return .none
        }
        return SupporterTier(rawValue: rawValue) ?? .none
    }
}

@Observable @MainActor
final class BrowserGameModel: Identifiable {
    let id: UUID
    let endpointName: String
    let connectionMode: BrowserConnectionMode
    let supporterTier: SupporterTier
    /// The session the advertising host belongs to (TXT record). A host advertises its own; a
    /// player's reconnect service advertises the session it joined, so a master only redials
    /// its own players. See CODE_AUDIT_Join §5.2.
    let sessionId: String?

    /// The name shown to the user. Only the legacy "<name>.MasterRPG" suffix is removed — a
    /// title containing a dot ("Vol. 2") must not be cut at it. See CODE_AUDIT_Join §5.10.
    var deviceName: String {
        endpointName.hasSuffix(Self.legacyNameSuffix) ? String(endpointName.dropLast(Self.legacyNameSuffix.count)) : endpointName
    }

    private static let legacyNameSuffix = ".MasterRPG"

    init(id: UUID, endpointName: String, connectionMode: BrowserConnectionMode, supporterTier: SupporterTier = .none, sessionId: String? = nil) {
        self.id = id
        self.endpointName = endpointName
        self.connectionMode = connectionMode
        self.supporterTier = supporterTier
        self.sessionId = sessionId
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
        case .waiting(let nWError):
            networkUpdateContinuation.yield(.browserWaiting(nWError))
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
