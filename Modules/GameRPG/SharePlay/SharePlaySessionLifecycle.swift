// @copyright André Trettin

import CoreRPG
import Foundation
import GroupActivities
import os.log

@MainActor
enum RPGSharePlay {
    static let store = RPGSharePlayController()
}

struct SharePlaySessionLifecycle: Sendable {
    private var sessionId: UUID?
    private var joinRequested = false
    private var configured = false

    mutating func prepare(sessionId: UUID) {
        self.sessionId = sessionId
        joinRequested = false
        configured = false
    }

    mutating func didRequestJoin(sessionId: UUID) {
        guard self.sessionId == sessionId else { return }
        joinRequested = true
    }

    mutating func didEnterJoinedState(sessionId: UUID) -> Bool {
        guard self.sessionId == sessionId, joinRequested, !configured else { return false }
        configured = true
        return true
    }

    func isCurrent(sessionId: UUID) -> Bool {
        self.sessionId == sessionId
    }

    mutating func reset() {
        sessionId = nil
        joinRequested = false
        configured = false
    }
}

struct SharePlaySessionOperationToken: Equatable, Sendable {
    let sessionId: UUID
    let generation: UInt64

    func canCommit(
        lifecycle: SharePlaySessionLifecycle,
        currentGeneration: UInt64,
        taskIsCancelled: Bool
    ) -> Bool {
        !taskIsCancelled &&
            lifecycle.isCurrent(sessionId: sessionId) &&
            generation == currentGeneration
    }
}

struct SharePlayActivationToken: Equatable, Sendable {
    let activityId: UUID
    let generation: UInt64
}

struct SharePlaySessionObserverToken: Equatable, Sendable {
    let generation: UInt64
}

struct SharePlaySessionObserverLifecycle: Sendable {
    private var generation: UInt64 = 0
    private(set) var acceptsSessions = false

    mutating func start(acceptsSessions: Bool) -> SharePlaySessionObserverToken {
        generation &+= 1
        self.acceptsSessions = acceptsSessions
        return SharePlaySessionObserverToken(generation: generation)
    }

    mutating func stop() {
        generation &+= 1
        acceptsSessions = false
    }

    func isCurrent(
        token: SharePlaySessionObserverToken,
        taskIsCancelled: Bool
    ) -> Bool {
        !taskIsCancelled && token.generation == generation
    }

    func canConfigure(
        token: SharePlaySessionObserverToken,
        taskIsCancelled: Bool
    ) -> Bool {
        acceptsSessions && isCurrent(token: token, taskIsCancelled: taskIsCancelled)
    }
}

enum SharePlayActivationSessionDisposition: Equatable, Sendable {
    case configure
    case leave
    case leaveAndStopCleanup
}

/// Binds local activation attempts to the exact RPGActivity later delivered by
/// sessions(). Cancellation cannot always abort the system activation await, so
/// an obsolete successful attempt is rejected when its tagged session arrives.
struct SharePlayActivationLifecycle: Sendable {
    private enum State: Equatable, Sendable {
        case active
        case obsolete
    }

    private var generation: UInt64 = 0
    private var currentToken: SharePlayActivationToken?
    private var states: [UUID: State] = [:]

    var hasObsoleteActivities: Bool {
        states.values.contains(.obsolete)
    }

    mutating func begin(activityId: UUID) -> SharePlayActivationToken {
        if let currentToken {
            states[currentToken.activityId] = .obsolete
        }
        generation &+= 1
        let token = SharePlayActivationToken(
            activityId: activityId,
            generation: generation
        )
        currentToken = token
        states[activityId] = .active
        return token
    }

    mutating func cancelCurrent() {
        if let currentToken {
            states[currentToken.activityId] = .obsolete
        }
        currentToken = nil
        generation &+= 1
    }

    func canCommit(
        token: SharePlayActivationToken,
        taskIsCancelled: Bool
    ) -> Bool {
        !taskIsCancelled &&
            token.generation == generation
    }

    mutating func didFinish(
        token: SharePlayActivationToken,
        activated: Bool
    ) {
        guard !activated else { return }
        states.removeValue(forKey: token.activityId)
        if currentToken == token {
            currentToken = nil
        }
    }

    mutating func dispositionForSession(
        activityId: UUID?,
        acceptsSessions: Bool
    ) -> SharePlayActivationSessionDisposition {
        var rejectedObsoleteActivity = false
        if let activityId, let state = states.removeValue(forKey: activityId) {
            if currentToken?.activityId == activityId {
                currentToken = nil
            }
            rejectedObsoleteActivity = state == .obsolete
        }

        if acceptsSessions {
            return rejectedObsoleteActivity ? .leave : .configure
        }
        return hasObsoleteActivities ? .leave : .leaveAndStopCleanup
    }
}
