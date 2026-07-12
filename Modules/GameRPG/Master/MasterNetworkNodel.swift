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

    /// Returns whether a connection with that id exists and the data was handed
    /// to it — false means the id is unknown here (e.g. a SharePlay participant)
    /// and the caller must deliver another way.
    @discardableResult
    func sendResponse(data: MessageMapper?, id: ConnectionController.ID) async -> Bool
    func sendResponse(data: MessageMapper?) async
    func sendResponse(data: MessageMapper?, except: ConnectionController.ID) async
}

@MainActor @Observable
final class MasterNetworkNodel {
    init(name: String = "Master Device") {
        self.name = name
    }
    
    var name: String
    var connections: [ConnectionController] = []
    var isStreaming: Bool = false
    
    @ObservationIgnored var browserManager: BrowserManager? = nil
    @ObservationIgnored var observeConnectionsTask: Task<Void, Never>? = nil
    @ObservationIgnored var connectionStartTasks: [ConnectionController.ID: Task<Void, Never>] = [:]
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

#if DEBUG
/// Test double (SpyingStub) for MasterNetworkControllable protocol.
///
/// **Type**: SpyingStub (combines Spy + Stub behavior)
/// - **Spy**: Records all calls for verification in tests
/// - **Stub**: Provides configurable responses
///
/// **Usage**:
/// ```swift
/// let spy = MasterNetworkControllableSpyingStub()
/// await spy.startStreaming()
/// #expect(spy.calledStartStreaming == 1)
/// ```
///
/// - Warning: `@unchecked Sendable` because this is a test-only spy that
///   is not actually thread-safe. Mutable counters are accessed without
///   synchronization. Safe because tests run sequentially within a single
///   test method.
final class MasterNetworkControllableSpyingStub: MasterNetworkControllable, @unchecked Sendable {
    // MARK: - Required Protocol Properties

    @MainActor
    let networkModel: MasterNetworkNodel

    // MARK: - Spy: Call Recording

    /// Number of times `startStreaming()` was called
    public var calledStartStreaming = 0
    /// Number of times `stopStreaming()` was called
    public var calledStopStreaming = 0
    /// Number of times `toggleStreaming()` was called
    public var calledToggleStreaming = 0
    /// Number of times `startProxyStreaming()` was called
    public var calledStartProxyStreaming = 0
    /// Number of times `sendResponse(data:id:)` was called
    public var calledSendResponseId = 0
    /// Stubbed delivery result for `sendResponse(data:id:)`
    public var sendResponseIdDelivered = true
    /// Number of times `sendResponse(data:)` was called
    public var calledSendResponseAll = 0
    /// Number of times `sendResponse(data:except:)` was called
    public var calledSendResponseExcept = 0

    // MARK: - Spy: Captured Arguments

    /// Last data sent via `sendResponse`
    public var lastSentData: MessageMapper?
    /// Last connection ID used in `sendResponse(data:id:)`
    public var lastSentToId: ConnectionController.ID?
    /// Last connection ID excluded in `sendResponse(data:except:)`
    public var lastExceptId: ConnectionController.ID?

    // MARK: - Initialization

    @MainActor
    init(networkModel: MasterNetworkNodel = MasterNetworkNodel()) {
        self.networkModel = networkModel
    }

    // MARK: - Protocol Methods

    @MainActor
    func startStreaming() {
        calledStartStreaming += 1
    }

    @MainActor
    func stopStreaming() {
        calledStopStreaming += 1
    }

    @MainActor
    func toggleStreaming() {
        calledToggleStreaming += 1
    }

    @MainActor
    func startProxyStreaming() {
        calledStartProxyStreaming += 1
    }

    @discardableResult
    func sendResponse(data: MessageMapper?, id: ConnectionController.ID) async -> Bool {
        calledSendResponseId += 1
        lastSentData = data
        lastSentToId = id
        return sendResponseIdDelivered
    }

    func sendResponse(data: MessageMapper?) async {
        calledSendResponseAll += 1
        lastSentData = data
    }

    func sendResponse(data: MessageMapper?, except: ConnectionController.ID) async {
        calledSendResponseExcept += 1
        lastSentData = data
        lastExceptId = except
    }
}

/// Test double (Spy) for MasterNetworkControllerDelegate protocol.
///
/// **Type**: Spy (records calls for verification)
///
/// **Usage**:
/// ```swift
/// let spy = MasterNetworkControllerDelegateSpyingStub()
/// await spy.masterReady(for: connectionId)
/// #expect(spy.calledReady == 1)
/// ```
///
/// - Warning: `@unchecked Sendable` because this is a test-only spy that
///   is not actually thread-safe. Safe because tests run sequentially.
final class MasterNetworkControllerDelegateSpyingStub: MasterNetworkControllerDelegate, @unchecked Sendable {
    // MARK: - Spy: Call Recording

    /// Number of times `masterLostPlayer(with:)` was called
    public private(set) var calledLostPlayer = 0
    /// Number of times `masterReady(for:)` was called
    public private(set) var calledReady = 0
    /// Number of times `masterReceived(data:for:fileJournal:)` was called
    public private(set) var calledReceived = 0

    // MARK: - Spy: Captured Arguments

    /// Last connection ID from lost player
    public private(set) var lastLostPlayerId: ConnectionController.ID?
    /// Last connection ID that became ready
    public private(set) var lastReadyId: ConnectionController.ID?
    /// Last received data
    public private(set) var lastReceivedData: Data?
    /// Last connection ID that sent data
    public private(set) var lastReceivedFromId: ConnectionController.ID?
    /// Last fileJournal flag value
    public private(set) var lastFileJournalFlag: Bool?

    // MARK: - Protocol Methods

    func masterLostPlayer(with connectionId: ConnectionController.ID) async {
        calledLostPlayer += 1
        lastLostPlayerId = connectionId
    }

    func masterReady(for connectionId: ConnectionController.ID) async {
        calledReady += 1
        lastReadyId = connectionId
    }

    func masterReceived(data: Data?, for connectionId: ConnectionController.ID, fileJournal: Bool) async {
        calledReceived += 1
        lastReceivedData = data
        lastReceivedFromId = connectionId
        lastFileJournalFlag = fileJournal
    }
}
#endif
