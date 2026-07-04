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
    var browserManager: BrowserManager { get }

    @MainActor func toggleConnection(to model: BrowserGameModel) async
    @MainActor func stop() async

    func request(with content: MessageMapper?) async
}

@MainActor @Observable
final class PlayerNetworkNodel {
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

    func reset(listener: (any ListenerManaging)?) {
        self.listener = listener
    }

    @ObservationIgnored var connectionController: ConnectionController? = nil
    @ObservationIgnored var listener: (any ListenerManaging)? = nil
    @ObservationIgnored var observeRemovalTask: Task<Void, Never>? = nil
    @ObservationIgnored var connectionStartTask: Task<Void, Never>? = nil
}

#if DEBUG
/// Test double (SpyingStub) for PlayerNetworkControllable protocol.
///
/// **Type**: SpyingStub (combines Spy + Stub behavior)
/// - **Spy**: Records all calls for verification in tests
/// - **Stub**: Provides configurable responses
///
/// **Usage**:
/// ```swift
/// let spy = PlayerNetworkControllableSpyingStub()
/// await spy.stop()
/// #expect(spy.calledStop == 1)
/// ```
///
/// - Warning: `@unchecked Sendable` because this is a test-only spy that
///   is not actually thread-safe. Mutable counters are accessed without
///   synchronization. Safe because tests run sequentially within a single
///   test method.
final class PlayerNetworkControllableSpyingStub: PlayerNetworkControllable, @unchecked Sendable {
    // MARK: - Required Protocol Properties

    let browserManager: BrowserManager
    @MainActor
    let networkModel: PlayerNetworkNodel

    // MARK: - Spy: Call Recording

    /// Number of times `stop()` was called
    public var calledStop = 0
    /// Number of times `toggleConnection(to:)` was called
    public var calledToggleConnection = 0
    /// Number of times `request(with:)` was called
    public var calledRequest = 0

    // MARK: - Spy: Captured Arguments

    /// Last game model passed to `toggleConnection(to:)`
    public var lastToggledGame: BrowserGameModel?
    /// Last message mapper passed to `request(with:)`
    public var lastRequestData: MessageMapper?

    // MARK: - Initialization

    @MainActor
    init(
        browserManager: BrowserManager = BrowserManager(),
        networkModel: PlayerNetworkNodel = PlayerNetworkNodel()
    ) {
        self.browserManager = browserManager
        self.networkModel = networkModel
    }

    // MARK: - Protocol Methods

    @MainActor
    func toggleConnection(to model: BrowserGameModel) async {
        calledToggleConnection += 1
        lastToggledGame = model
    }

    @MainActor
    func stop() async {
        calledStop += 1
    }

    func request(with content: MessageMapper?) async {
        calledRequest += 1
        lastRequestData = content
    }
}

/// Test double (SpyingStub) for PlayerNetworkControllerDelegate protocol.
///
/// **Type**: Spy (records calls for verification)
///
/// **Usage**:
/// ```swift
/// let spy = PlayerNetworkControllerDelegateSpyingStub()
/// await spy.playerReady()
/// #expect(spy.calledReady == 1)
/// ```
///
/// - Warning: `@unchecked Sendable` because this is a test-only spy that
///   is not actually thread-safe. Safe because tests run sequentially.
final class PlayerNetworkControllerDelegateSpyingStub: PlayerNetworkControllerDelegate, @unchecked Sendable {
    // MARK: - Spy: Call Recording

    /// Number of times `playerLostMaster()` was called
    public private(set) var calledLostMaster = 0
    /// Number of times `playerReady()` was called
    public private(set) var calledReady = 0
    /// Number of times `playerReceived(data:)` was called
    public private(set) var calledReceived = 0

    // MARK: - Spy: Captured Arguments

    /// Last data received in `playerReceived(data:)`
    public private(set) var lastReceivedData: Data?

    // MARK: - Protocol Methods

    func playerLostMaster() async {
        calledLostMaster += 1
    }

    func playerReceived(data: Data?) async {
        calledReceived += 1
        lastReceivedData = data
    }

    func playerReady() async {
        calledReady += 1
    }
}
#endif
