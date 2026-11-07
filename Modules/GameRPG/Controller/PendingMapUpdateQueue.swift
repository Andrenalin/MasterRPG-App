// @copyright André Trettin

import CoreRPG
import Foundation

/// The live part of a map can arrive before the map itself: Messenger is faster than the
/// Journal. The newest content, state and battle round of each map wait here until the map is
/// there, together with the counters of what was applied and the times the map was asked for.
/// See CODE_AUDIT_Audio2 §9.15.
struct PendingMapUpdateQueue: Sendable {
    private struct PendingMapUpdate: Sendable {
        let data: NetworkCodableDataType
        let counter: Int
    }

    private var pendingMapContentUpdates: [UUID: PendingMapUpdate] = [:]
    private var pendingMapStates: [UUID: PendingMapUpdate] = [:]
    private var pendingBattleRoundUpdates: [UUID: NetworkCodableDataType] = [:]
    private var lastMapContentCounters: [UUID: Int] = [:]
    private var lastMapStateCounters: [UUID: Int] = [:]
    /// When each map was last asked for, so a burst of states for a map that is still on its
    /// way asks once.
    private var lastMapRequests: [UUID: ContinuousClock.Instant] = [:]
    static let mapRequestInterval: Duration = .seconds(10)

    mutating func queueMapContentUpdate(_ data: NetworkCodableDataType, counter: Int) {
        guard shouldApplyMapContentUpdate(itemId: data.id, counter: counter) else { return }
        if let current = pendingMapContentUpdates[data.id], counter != 0, current.counter >= counter {
            return
        }
        pendingMapContentUpdates[data.id] = PendingMapUpdate(data: data, counter: counter)
    }

    func pendingMapContentUpdate(for itemId: UUID) -> (data: NetworkCodableDataType, counter: Int)? {
        guard let pending = pendingMapContentUpdates[itemId] else { return nil }
        return (pending.data, pending.counter)
    }

    mutating func discardPendingMapContentUpdate(itemId: UUID) {
        pendingMapContentUpdates[itemId] = nil
    }

    /// Also asked before a map package is imported over a map this player already holds: a
    /// package that arrives after a newer content update would roll the map back.
    func shouldApplyMapContentUpdate(itemId: UUID, counter: Int) -> Bool {
        counter == 0 || counter > (lastMapContentCounters[itemId] ?? 0)
    }

    mutating func markMapContentApplied(itemId: UUID, counter: Int) {
        if counter > 0 {
            lastMapContentCounters[itemId] = max(lastMapContentCounters[itemId] ?? 0, counter)
        }
        if let pending = pendingMapContentUpdates[itemId], pending.counter <= counter {
            pendingMapContentUpdates[itemId] = nil
        }
    }

    mutating func queueMapState(_ data: NetworkCodableDataType, counter: Int) {
        guard shouldApplyMapState(itemId: data.id, counter: counter) else { return }
        if let current = pendingMapStates[data.id], counter != 0, current.counter >= counter {
            return
        }
        pendingMapStates[data.id] = PendingMapUpdate(data: data, counter: counter)
    }

    func pendingMapState(for itemId: UUID) -> (data: NetworkCodableDataType, counter: Int)? {
        guard let pending = pendingMapStates[itemId] else { return nil }
        return (pending.data, pending.counter)
    }

    mutating func discardPendingMapState(itemId: UUID) {
        pendingMapStates[itemId] = nil
    }

    func shouldApplyMapState(itemId: UUID, counter: Int) -> Bool {
        counter == 0 || counter > (lastMapStateCounters[itemId] ?? 0)
    }

    mutating func markMapStateApplied(itemId: UUID, counter: Int) {
        if counter > 0 {
            lastMapStateCounters[itemId] = max(lastMapStateCounters[itemId] ?? 0, counter)
        }
        pendingMapStates[itemId] = nil
    }

    /// The replay slot of a battle round update that arrived before its map. Always
    /// overwrites: a later update is at least as recent, and `applyRemoteState`'s own sequence
    /// check decides whether a replay is still worth applying. See CODE_AUDIT §5.2.
    mutating func queueBattleRoundUpdate(_ data: NetworkCodableDataType) {
        pendingBattleRoundUpdates[data.id] = data
    }

    func pendingBattleRoundUpdate(for itemId: UUID) -> NetworkCodableDataType? {
        pendingBattleRoundUpdates[itemId]
    }

    mutating func discardPendingBattleRoundUpdate(itemId: UUID) {
        pendingBattleRoundUpdates[itemId] = nil
    }

    /// Records a request for the map that answers a reveal, which is always sent.
    mutating func noteMapRequest(itemId: UUID, now: ContinuousClock.Instant = .now) {
        lastMapRequests[itemId] = now
    }

    /// Whether a map state may ask for its map: not while a request of the last
    /// `mapRequestInterval` may still be answered.
    mutating func mayRequestMap(itemId: UUID, now: ContinuousClock.Instant = .now) -> Bool {
        if let last = lastMapRequests[itemId], last.duration(to: now) < Self.mapRequestInterval {
            return false
        }
        lastMapRequests[itemId] = now
        return true
    }

    mutating func reset() {
        pendingMapContentUpdates.removeAll()
        pendingMapStates.removeAll()
        pendingBattleRoundUpdates.removeAll()
        lastMapContentCounters.removeAll()
        lastMapStateCounters.removeAll()
        lastMapRequests.removeAll()
    }
}
