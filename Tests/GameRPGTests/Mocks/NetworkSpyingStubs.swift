// @copyright André Trettin

import CoreRPG
import Foundation
@testable import GameRPG

// Test doubles that used to live in the GameRPG module behind `#if DEBUG`.
// See CODE_AUDIT_15 §9.8.

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
