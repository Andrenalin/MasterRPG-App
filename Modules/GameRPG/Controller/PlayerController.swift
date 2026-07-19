// @copyright André Trettin

import AdventureRPG
import CoreRPG
import DiceRPG
import Foundation
import os.log
import AudioRPG
import MapRPG
import PhotoRPG
import TableRPG
import CharacterRPG
import WeatherRPG
import PdfRPG
import SpaceRPG
#if os(macOS)
import AppKit
#else
import UIKit
#endif

private enum PlayerPhotoRevealValidation: Sendable {
    case valid
    case awaitingAuthoritativeList
    case mismatch
}

private enum PlayerPdfRevealValidation: Sendable {
    case valid
    case awaitingAuthoritativeList
    case mismatch
}

private enum PlayerSpaceRevealValidation: Sendable {
    case valid
    case awaitingAuthoritativeList
    case mismatch
}

private enum PlayerSpaceTransformValidation: Sendable {
    case valid
    case awaitingAuthoritativeList
    case mismatch
}

private enum PlayerMapPinApplication: Sendable {
    case applied
    case awaitingMapGeneration
    case rejected
}

enum SharePlayMasterParticipantAcceptance: Equatable, Sendable {
    case newlyBound
    case rebound
    case alreadyBound
    case rejected
}

@MainActor @Observable
final class PlayerControllerModel: Sendable {
    private struct DeferredPhotoRevealKey: Hashable, Sendable {
        let masterId: UUID
        let senderId: UUID
    }

    private struct DeferredPdfRevealKey: Hashable, Sendable {
        let masterId: UUID
        let senderId: UUID
    }

    private struct DeferredSpaceRevealKey: Hashable, Sendable {
        let masterId: UUID
        let senderId: UUID
    }

    private struct DeferredMapPinKey: Hashable, Sendable {
        let itemId: UUID
        let pinId: UUID
        let senderId: UUID
        let version: Int
        let assetVersion: Int?
        let contentVersion: Int?
    }

    private struct DeferredMapPin: Sendable {
        let model: GameNetworkModel
        let pinTimestamp: TimeInterval
    }

    private struct DeferredSpaceTransformKey: Hashable, Sendable {
        let masterId: UUID
        let senderId: UUID
        let itemId: UUID
        let version: Int
    }

    private struct PresentationIntent {
        let module: NetworkModules
        let counter: Int
        let itemId: UUID
        let version: Int
        let timestamp: TimeInterval
        let senderID: UUID
    }

    private struct PendingMapContentUpdate: Sendable {
        let data: NetworkCodableDataType
        let counter: Int
    }

    private struct PendingMapState: Sendable {
        let data: NetworkCodableDataType
        let counter: Int
    }

    private struct PendingMapRepair: Equatable, Sendable {
        let assetVersion: Int?
        let contentVersion: Int?
        var presentsMap: Bool
        var counter: Int
    }

    var gameUpdateType: NetworkModules = .none
    var messageCounter: Int = 0
    private var outgoingMessageCounter: Int = 1
    private var lastMasterStateCounters: [UUID: Int] = [:]
    private var lastAudioListCounters: [UUID: Int] = [:]
    private var lastPhotoListCounters: [UUID: Int] = [:]
    private var lastPdfListCounters: [UUID: Int] = [:]
    private var lastSpaceListCounters: [UUID: Int] = [:]
    private var authoritativePhotoListMasters: Set<UUID> = []
    private var authoritativePdfListMasters: Set<UUID> = []
    private var authoritativeSpaceListMasters: Set<UUID> = []
    private var deferredPhotoReveals: [DeferredPhotoRevealKey: GameNetworkModel] = [:]
    private var deferredPhotoRevealOrder: [DeferredPhotoRevealKey] = []
    private var deferredPdfReveals: [DeferredPdfRevealKey: GameNetworkModel] = [:]
    private var deferredPdfRevealOrder: [DeferredPdfRevealKey] = []
    private var deferredSpaceReveals: [DeferredSpaceRevealKey: GameNetworkModel] = [:]
    private var deferredSpaceRevealOrder: [DeferredSpaceRevealKey] = []
    private var deferredMapPins: [DeferredMapPinKey: DeferredMapPin] = [:]
    private var deferredMapPinOrder: [DeferredMapPinKey] = []
    private var deferredSpaceTransforms: [DeferredSpaceTransformKey: GameNetworkModel] = [:]
    private var deferredSpaceTransformOrder: [DeferredSpaceTransformKey] = []
    private var presentationIntents: [UUID: PresentationIntent] = [:]
    /// Physical GroupSession participant that first established the current
    /// logical master. Logical UUIDs travel inside an untrusted envelope, so a
    /// different SharePlay peer must not impersonate that master after learning
    /// its UUID from a broadcast.
    private var sharePlayMasterParticipantId: UUID?
    private var resynchronizeAfterSharePlayMasterRebind = false
    var lostMaster: Bool = true
    var hasSendPlayer = false
    var asGameMaster = false
    var sendCharacterTask: Task<Void, Never>?
    var sendCharacterTaskId: UUID?
    var proxyFocusTask: Task<Void, Never>?
    var proxyFocusTaskId: UUID?
    // Map ids with an in-flight full-map re-request, so a burst of mapState
    // messages cannot trigger a request storm. Cleared when map data arrives.
    var pendingMapRequests: Set<UUID> = []
    // Audio reveals waiting for a full payload. SharePlay journals deliver the
    // bytes as a non-presenting store so every participant and proxy can save it.
    var pendingAudioRequests: Set<UUID> = []
    // Photo ids already requested for repair. An id is only released when the
    // repair actually produced a local file — a permanently failing photo is
    // requested once instead of looping master responses forever.
    var requestedRepairIds: Set<UUID> = []
    // PDF ids with one outstanding master-asset repair. This prevents a missing
    // or corrupt file from bouncing reveal/store requests forever.
    var requestedPdfRepairIds: Set<UUID> = []
    // Space ids with one outstanding full-file repair request. A permanently
    // unavailable USDZ must not create an endless reveal/store response loop.
    var requestedSpaceRepairIds: Set<UUID> = []
    /// Latest structural update received before its Journal-backed base map.
    /// Only one value per map is retained, so interleaved chunk streams cannot
    /// roll a newer editor refresh back.
    private var pendingMapContentUpdates: [UUID: PendingMapContentUpdate] = [:]
    private var pendingMapStates: [UUID: PendingMapState] = [:]
    private var lastMapContentUpdateCounters: [UUID: Int] = [:]
    private var lastFullMapContentCounters: [UUID: Int] = [:]
    private var lastMapStateCounters: [UUID: Int] = [:]
    private var mapContentVersions: [UUID: Int] = [:]
    private var pendingMapRepairs: [UUID: PendingMapRepair] = [:]
    private var pendingMapBackgroundRepairs: [UUID: PendingMapRepair] = [:]

    func increaseMessageCounter() {
        messageCounter += 1
    }

    func nextOutgoingMessageCounter() -> Int {
        defer { outgoingMessageCounter += 1 }
        return outgoingMessageCounter
    }

    func shouldApplyMasterState(from masterId: UUID, counter: Int) -> Bool {
        guard counter > 0 else { return true }
        guard counter > (lastMasterStateCounters[masterId] ?? 0) else { return false }
        lastMasterStateCounters[masterId] = counter
        return true
    }

    func hasAppliedMasterState(from masterId: UUID, counter: Int) -> Bool {
        counter == 0 || lastMasterStateCounters[masterId] == counter
    }

    func resetMasterStateSequence() {
        lastMasterStateCounters.removeAll()
    }

    func acceptSharePlayMasterParticipant(
        id: UUID,
        isCompleteMasterBroadcast: Bool
    ) -> SharePlayMasterParticipantAcceptance {
        guard let sharePlayMasterParticipantId else {
            // A physical source may establish authority only with the complete
            // state that production master broadcasts attach. In particular,
            // after the pinned participant leaves, a peer that merely copied
            // the public logical master UUID cannot win the rebind race with a
            // state-less command.
            guard isCompleteMasterBroadcast else { return .rejected }
            self.sharePlayMasterParticipantId = id
            if resynchronizeAfterSharePlayMasterRebind {
                resynchronizeAfterSharePlayMasterRebind = false
                return .rebound
            }
            return .newlyBound
        }
        return sharePlayMasterParticipantId == id ? .alreadyBound : .rejected
    }

    @discardableResult
    func removeSharePlayMasterParticipant(id: UUID) -> Bool {
        guard sharePlayMasterParticipantId == id else { return false }
        sharePlayMasterParticipantId = nil
        resynchronizeAfterSharePlayMasterRebind = true
        return true
    }

    func resetSharePlayMasterParticipant() {
        sharePlayMasterParticipantId = nil
        resynchronizeAfterSharePlayMasterRebind = false
    }

    func isSharePlayMasterParticipant(id: UUID) -> Bool {
        sharePlayMasterParticipantId == id
    }

    func canApplyAudioList(from masterId: UUID, counter: Int) -> Bool {
        guard counter >= 0 else { return false }
        guard counter > 0 else { return true }
        return counter > (lastAudioListCounters[masterId] ?? 0)
    }

    func recordAudioList(counter: Int, from masterId: UUID) {
        guard counter > 0 else { return }
        lastAudioListCounters[masterId] = counter
    }

    func resetAudioListSequence() {
        lastAudioListCounters.removeAll()
    }

    func canApplyPhotoList(from masterId: UUID, counter: Int) -> Bool {
        guard counter >= 0 else { return false }
        guard counter > 0 else { return true }
        return counter > (lastPhotoListCounters[masterId] ?? 0)
    }

    func recordPhotoList(counter: Int, from masterId: UUID) {
        authoritativePhotoListMasters.insert(masterId)
        if counter > 0 {
            lastPhotoListCounters[masterId] = counter
        }
    }

    func hasAuthoritativePhotoList(from masterId: UUID) -> Bool {
        authoritativePhotoListMasters.contains(masterId)
    }

    /// Retains only the latest reveal from each sender and preserves the local
    /// arrival order across senders. The fixed cap prevents a missing report
    /// from growing memory without bound.
    func deferPhotoReveal(_ model: GameNetworkModel) {
        let key = DeferredPhotoRevealKey(masterId: model.masterId, senderId: model.sender.id)
        deferredPhotoRevealOrder.removeAll { $0 == key }
        deferredPhotoRevealOrder.append(key)
        deferredPhotoReveals[key] = model

        let maximumDeferredPhotoReveals = 32
        while deferredPhotoRevealOrder.count > maximumDeferredPhotoReveals {
            let oldestKey = deferredPhotoRevealOrder.removeFirst()
            deferredPhotoReveals[oldestKey] = nil
        }
    }

    func deferredPhotoReveals(from masterId: UUID) -> [GameNetworkModel] {
        deferredPhotoRevealOrder.compactMap { key in
            guard key.masterId == masterId else { return nil }
            return deferredPhotoReveals[key]
        }
    }

    func removeDeferredPhotoReveal(_ model: GameNetworkModel) {
        let key = DeferredPhotoRevealKey(masterId: model.masterId, senderId: model.sender.id)
        deferredPhotoReveals[key] = nil
        deferredPhotoRevealOrder.removeAll { $0 == key }
    }

    func removeDeferredPhotoReveals(from masterId: UUID) {
        let keys = deferredPhotoRevealOrder.filter { $0.masterId == masterId }
        for key in keys {
            deferredPhotoReveals[key] = nil
        }
        deferredPhotoRevealOrder.removeAll { $0.masterId == masterId }
    }

    func resetPhotoListSequence() {
        lastPhotoListCounters.removeAll()
        authoritativePhotoListMasters.removeAll()
        deferredPhotoReveals.removeAll()
        deferredPhotoRevealOrder.removeAll()
    }

    func canApplyPdfList(from masterId: UUID, counter: Int) -> Bool {
        guard counter >= 0 else { return false }
        guard counter > 0 else { return true }
        return counter > (lastPdfListCounters[masterId] ?? 0)
    }

    func recordPdfList(counter: Int, from masterId: UUID) {
        authoritativePdfListMasters.insert(masterId)
        if counter > 0 {
            lastPdfListCounters[masterId] = counter
        }
    }

    func hasAuthoritativePdfList(from masterId: UUID) -> Bool {
        authoritativePdfListMasters.contains(masterId)
    }

    func deferPdfReveal(_ model: GameNetworkModel) {
        let key = DeferredPdfRevealKey(masterId: model.masterId, senderId: model.sender.id)
        deferredPdfRevealOrder.removeAll { $0 == key }
        deferredPdfRevealOrder.append(key)
        deferredPdfReveals[key] = model

        let maximumDeferredPdfReveals = 32
        while deferredPdfRevealOrder.count > maximumDeferredPdfReveals {
            let oldestKey = deferredPdfRevealOrder.removeFirst()
            deferredPdfReveals[oldestKey] = nil
        }
    }

    func deferredPdfReveals(from masterId: UUID) -> [GameNetworkModel] {
        deferredPdfRevealOrder.compactMap { key in
            guard key.masterId == masterId else { return nil }
            return deferredPdfReveals[key]
        }
    }

    func removeDeferredPdfReveal(_ model: GameNetworkModel) {
        let key = DeferredPdfRevealKey(masterId: model.masterId, senderId: model.sender.id)
        deferredPdfReveals[key] = nil
        deferredPdfRevealOrder.removeAll { $0 == key }
    }

    func removeDeferredPdfReveals(from masterId: UUID) {
        let keys = deferredPdfRevealOrder.filter { $0.masterId == masterId }
        for key in keys {
            deferredPdfReveals[key] = nil
        }
        deferredPdfRevealOrder.removeAll { $0.masterId == masterId }
    }

    func resetPdfListSequence() {
        lastPdfListCounters.removeAll()
        authoritativePdfListMasters.removeAll()
        deferredPdfReveals.removeAll()
        deferredPdfRevealOrder.removeAll()
    }

    func canApplySpaceList(from masterId: UUID, counter: Int) -> Bool {
        guard counter >= 0 else { return false }
        guard counter > 0 else { return true }
        return counter > (lastSpaceListCounters[masterId] ?? 0)
    }

    func recordSpaceList(counter: Int, from masterId: UUID) {
        authoritativeSpaceListMasters.insert(masterId)
        if counter > 0 {
            lastSpaceListCounters[masterId] = counter
        }
    }

    func hasAuthoritativeSpaceList(from masterId: UUID) -> Bool {
        authoritativeSpaceListMasters.contains(masterId)
    }

    func deferSpaceReveal(_ model: GameNetworkModel) {
        let key = DeferredSpaceRevealKey(masterId: model.masterId, senderId: model.sender.id)
        deferredSpaceRevealOrder.removeAll { $0 == key }
        deferredSpaceRevealOrder.append(key)
        deferredSpaceReveals[key] = model

        let maximumDeferredSpaceReveals = 32
        while deferredSpaceRevealOrder.count > maximumDeferredSpaceReveals {
            let oldestKey = deferredSpaceRevealOrder.removeFirst()
            deferredSpaceReveals[oldestKey] = nil
        }
    }

    func deferredSpaceReveals(from masterId: UUID) -> [GameNetworkModel] {
        deferredSpaceRevealOrder.compactMap { key in
            guard key.masterId == masterId else { return nil }
            return deferredSpaceReveals[key]
        }
    }

    func removeDeferredSpaceReveal(_ model: GameNetworkModel) {
        let key = DeferredSpaceRevealKey(masterId: model.masterId, senderId: model.sender.id)
        deferredSpaceReveals[key] = nil
        deferredSpaceRevealOrder.removeAll { $0 == key }
    }

    func removeDeferredSpaceReveals(from masterId: UUID) {
        let keys = deferredSpaceRevealOrder.filter { $0.masterId == masterId }
        for key in keys {
            deferredSpaceReveals[key] = nil
        }
        deferredSpaceRevealOrder.removeAll { $0.masterId == masterId }
    }

    func resetSpaceListSequence() {
        lastSpaceListCounters.removeAll()
        authoritativeSpaceListMasters.removeAll()
        deferredSpaceReveals.removeAll()
        deferredSpaceRevealOrder.removeAll()
        deferredSpaceTransforms.removeAll()
        deferredSpaceTransformOrder.removeAll()
    }

    /// Retains one current event for every sender/item/version while the
    /// authoritative Space availability snapshot is still in flight. Sender is
    /// part of the key because a temporarily unknown sender must not suppress an
    /// older transform from a sender the master has already authorized.
    func deferSpaceTransform(_ model: GameNetworkModel) {
        guard model.sender.role == .player,
              model.type == .update,
              model.subType == .spaceTransform,
              model.data.type == .space,
              GameNetworkModel.acceptsEventTimestamp(model.timestamp)
        else { return }

        let key = DeferredSpaceTransformKey(
            masterId: model.masterId,
            senderId: model.sender.id,
            itemId: model.data.id,
            version: model.data.effectiveAssetVersion
        )
        if let current = deferredSpaceTransforms[key],
           !Self.groupEvent(current, comesBefore: model) {
            return
        }

        deferredSpaceTransformOrder.removeAll { $0 == key }
        deferredSpaceTransformOrder.append(key)
        deferredSpaceTransforms[key] = model

        let maximumDeferredSpaceTransforms = 64
        while deferredSpaceTransformOrder.count > maximumDeferredSpaceTransforms {
            deferredSpaceTransforms[deferredSpaceTransformOrder.removeFirst()] = nil
        }
    }

    func deferredSpaceTransforms(from masterId: UUID) -> [GameNetworkModel] {
        deferredSpaceTransformOrder.compactMap { key in
            guard key.masterId == masterId else { return nil }
            return deferredSpaceTransforms[key]
        }.sorted { Self.groupEvent($0, comesBefore: $1) }
    }

    func removeDeferredSpaceTransform(_ model: GameNetworkModel) {
        let key = DeferredSpaceTransformKey(
            masterId: model.masterId,
            senderId: model.sender.id,
            itemId: model.data.id,
            version: model.data.effectiveAssetVersion
        )
        deferredSpaceTransforms[key] = nil
        deferredSpaceTransformOrder.removeAll { $0 == key }
    }

    /// A Map pin can overtake the Journal-backed Map package that establishes
    /// its generation. Keep only the newest payload timestamp for a pin within
    /// each advertised generation. Other generations remain bounded in case a
    /// pin overtook more than one Journal-backed Map update.
    func deferMapPin(_ model: GameNetworkModel) {
        guard model.sender.role == .player,
              model.type == .update,
              model.subType == .mapPin,
              model.data.type == .map,
              let data = model.data.data,
              let pin = try? JSONDecoder().decode(MapPinModel.self, from: data),
              GameNetworkModel.acceptsEventTimestamp(pin.timeInterval)
        else { return }

        let key = DeferredMapPinKey(
            itemId: model.data.id,
            pinId: pin.id,
            senderId: model.sender.id,
            version: model.data.version,
            assetVersion: model.data.assetVersion,
            contentVersion: model.data.contentVersion
        )
        if let current = deferredMapPins[key],
           pin.timeInterval <= current.pinTimestamp {
            return
        }

        deferredMapPinOrder.removeAll { $0 == key }
        deferredMapPinOrder.append(key)
        deferredMapPins[key] = DeferredMapPin(
            model: model,
            pinTimestamp: pin.timeInterval
        )

        let maximumDeferredMapPins = 64
        while deferredMapPinOrder.count > maximumDeferredMapPins {
            deferredMapPins[deferredMapPinOrder.removeFirst()] = nil
        }
    }

    func consumeDeferredMapPins(
        for itemId: UUID,
        matching generation: NetworkCodableDataType
    ) -> [GameNetworkModel] {
        let matchingKeys = deferredMapPinOrder.filter { key in
            key.itemId == itemId &&
                key.version == generation.version &&
                key.assetVersion == generation.assetVersion &&
                key.contentVersion == generation.contentVersion
        }
        let matching = matchingKeys.compactMap { key -> DeferredMapPin? in
            return deferredMapPins[key]
        }.sorted { $0.pinTimestamp < $1.pinTimestamp }

        for key in matchingKeys {
            deferredMapPins[key] = nil
        }
        let consumedKeys = Set(matchingKeys)
        deferredMapPinOrder.removeAll { consumedKeys.contains($0) }
        return matching.map(\.model)
    }

    private static func groupEvent(
        _ lhs: GameNetworkModel,
        comesBefore rhs: GameNetworkModel
    ) -> Bool {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp < rhs.timestamp
        }
        if lhs.sender.id == rhs.sender.id, lhs.counter != rhs.counter {
            return lhs.counter < rhs.counter
        }
        if lhs.sender.id != rhs.sender.id {
            return lhs.sender.id.uuidString < rhs.sender.id.uuidString
        }
        return (lhs.messageID?.uuidString ?? "") < (rhs.messageID?.uuidString ?? "")
    }

    /// Accepts presentation content according to the latest master intent, not
    /// according to which transport happened to finish first.
    ///
    /// A repair reveal's freshly minted counter must
    /// not make an older item current again, so it is accepted only when it
    /// matches the desired item. Older untargeted content for that same desired
    /// item remains useful as a delayed full-payload delivery.
    func shouldProcessPresentation(
        from masterId: UUID,
        senderID: UUID = GameDeliveryMessageID.legacySessionID,
        module: NetworkModules,
        itemId: UUID,
        version: Int,
        counter: Int,
        timestamp: TimeInterval = 0,
        isRepair: Bool,
        allowsUnversionedStateRepair: Bool = false
    ) -> Bool {
        guard GameNetworkModel.acceptsEventTimestamp(timestamp) else {
            return false
        }

        guard let current = presentationIntents[masterId] else {
            presentationIntents[masterId] = PresentationIntent(
                module: module,
                counter: counter,
                itemId: itemId,
                version: version,
                timestamp: timestamp,
                senderID: senderID
            )
            return true
        }

        if isRepair {
            return acceptsCurrentPresentation(
                current,
                from: masterId,
                module: module,
                itemId: itemId,
                version: version,
                allowsUnversionedStateRepair: allowsUnversionedStateRepair
            )
        }

        guard replacesCurrentPresentation(
            current,
            from: masterId,
            senderID: senderID,
            counter: counter,
            timestamp: timestamp
        ) else {
            return acceptsCurrentPresentation(
                current,
                from: masterId,
                module: module,
                itemId: itemId,
                version: version
            )
        }

        let recordedVersion = if current.module == module,
                                 current.itemId == itemId,
                                 version == 0 {
            current.version
        } else {
            version
        }
        presentationIntents[masterId] = PresentationIntent(
            module: module,
            counter: counter,
            itemId: itemId,
            version: recordedVersion,
            timestamp: timestamp,
            senderID: senderID
        )
        return true
    }

    /// Decides only whether an incoming intent replaces the retained intent.
    /// A `false` result can still accept delayed bytes for the retained item in
    /// `acceptsCurrentPresentation` without changing this causal state.
    private func replacesCurrentPresentation(
        _ current: PresentationIntent,
        from masterId: UUID,
        senderID: UUID,
        counter: Int,
        timestamp: TimeInterval
    ) -> Bool {
        let sameSender = senderID == current.senderID
        let incomingIsCurrentFormat = timestamp > 0
        let currentIsCurrentFormat = current.timestamp > 0

        if sameSender {
            switch (incomingIsCurrentFormat, currentIsCurrentFormat) {
            case (true, true):
                return timestamp > current.timestamp ||
                    (timestamp == current.timestamp && counter > current.counter)
            case (true, false):
                return true
            case (false, true):
                return false
            case (false, false):
                // Counters are meaningful only inside one sender's sequence.
                // Counter zero is unsequenced legacy data, so its latest
                // arrival remains compatible with the previous behavior.
                return counter == 0 || counter > current.counter
            }
        }

        // Never compare counters from different senders: their sequences are
        // independent. A timestamped intent carries stronger causal evidence
        // than a legacy one, irrespective of which participant sent it.
        switch (incomingIsCurrentFormat, currentIsCurrentFormat) {
        case (true, false):
            return true
        case (false, true):
            return false
        case (true, true):
            let incomingIsMaster = senderID == masterId
            let currentIsMaster = current.senderID == masterId

            // A master envelope is the canonical relay/correction for a player
            // presentation. Its arrival is causally later even when the two
            // devices' bounded wall clocks disagree. In the opposite direction
            // a player must still carry a strictly newer timestamp.
            if incomingIsMaster != currentIsMaster {
                return incomingIsMaster || timestamp > current.timestamp
            }
            if timestamp != current.timestamp {
                return timestamp > current.timestamp
            }

            // Two player events retain a deterministic tie break so every peer
            // converges even if transport arrival order differs.
            return senderID.uuidString > current.senderID.uuidString
        case (false, false):
            // Legacy envelopes have no cross-sender causal clock. Prefer the
            // canonical master when authority differs; otherwise preserve the
            // documented last-arrival behavior for rare player presentations.
            let incomingIsMaster = senderID == masterId
            let currentIsMaster = current.senderID == masterId
            if incomingIsMaster != currentIsMaster {
                return incomingIsMaster
            }
            return true
        }
    }

    private func acceptsCurrentPresentation(
        _ current: PresentationIntent,
        from masterId: UUID,
        module: NetworkModules,
        itemId: UUID,
        version: Int,
        allowsUnversionedStateRepair: Bool = false
    ) -> Bool {
        guard current.module == module, current.itemId == itemId else { return false }
        guard current.version == 0 ||
                version == current.version ||
                (allowsUnversionedStateRepair && version == 0)
        else { return false }

        // Version zero means the legacy intent did not provide a fingerprint.
        // Once matching bytes arrive, retain their exact version so a later
        // same-item payload cannot replace them arbitrarily.
        if current.version == 0, version != 0 {
            presentationIntents[masterId] = PresentationIntent(
                module: current.module,
                counter: current.counter,
                itemId: current.itemId,
                version: version,
                timestamp: current.timestamp,
                senderID: current.senderID
            )
        }
        return true
    }

    func resetPresentationSequence() {
        presentationIntents.removeAll()
    }

    func queueMapContentUpdate(_ data: NetworkCodableDataType, counter: Int) {
        let appliedCounter = max(
            lastMapContentUpdateCounters[data.id] ?? 0,
            lastFullMapContentCounters[data.id] ?? 0
        )
        guard counter == 0 || counter > appliedCounter else { return }
        if let current = pendingMapContentUpdates[data.id], counter != 0, current.counter >= counter {
            return
        }
        pendingMapContentUpdates[data.id] = PendingMapContentUpdate(data: data, counter: counter)
    }

    func pendingMapContentUpdate(for itemId: UUID) -> (data: NetworkCodableDataType, counter: Int)? {
        guard let pending = pendingMapContentUpdates[itemId] else { return nil }
        return (pending.data, pending.counter)
    }

    func discardPendingMapContentUpdate(itemId: UUID) {
        pendingMapContentUpdates[itemId] = nil
    }

    func queueMapState(_ data: NetworkCodableDataType, counter: Int) {
        guard shouldApplyMapState(itemId: data.id, counter: counter) else { return }
        if let current = pendingMapStates[data.id],
           counter != 0,
           current.counter >= counter {
            return
        }
        pendingMapStates[data.id] = PendingMapState(data: data, counter: counter)
    }

    func pendingMapState(for itemId: UUID) -> (data: NetworkCodableDataType, counter: Int)? {
        guard let pending = pendingMapStates[itemId] else { return nil }
        return (pending.data, pending.counter)
    }

    func discardPendingMapState(itemId: UUID) {
        pendingMapStates[itemId] = nil
    }

    func shouldApplyMapContentUpdate(itemId: UUID, counter: Int) -> Bool {
        counter == 0 || counter > max(
            lastMapContentUpdateCounters[itemId] ?? 0,
            lastFullMapContentCounters[itemId] ?? 0
        )
    }

    func shouldApplyMapState(itemId: UUID, counter: Int) -> Bool {
        if counter == 0 {
            return lastMapStateCounters[itemId] == nil
        }
        return counter > (lastMapStateCounters[itemId] ?? 0)
    }

    func markMapStateApplied(itemId: UUID, counter: Int) {
        if counter > 0 {
            lastMapStateCounters[itemId] = counter
        }
        pendingMapStates[itemId] = nil
    }

    /// A Journal-backed full map may finish after a newer messenger mapUpdate.
    /// Importing that older snapshot would roll structural metadata back even
    /// though its background asset is still valid.
    func shouldImportFullMapContent(itemId: UUID, counter: Int) -> Bool {
        counter == 0 || counter > max(
            lastMapContentUpdateCounters[itemId] ?? 0,
            lastFullMapContentCounters[itemId] ?? 0
        )
    }

    func markMapContentUpdateApplied(itemId: UUID, counter: Int, contentVersion: Int?) {
        if counter > 0 {
            lastMapContentUpdateCounters[itemId] = counter
        }
        mapContentVersions[itemId] = contentVersion
        pendingMapContentUpdates[itemId] = nil
    }

    func recordFullMapContentVersion(itemId: UUID, contentVersion: Int?, counter: Int) {
        guard shouldImportFullMapContent(itemId: itemId, counter: counter) else { return }
        mapContentVersions[itemId] = contentVersion
        if counter > 0 {
            lastFullMapContentCounters[itemId] = max(lastFullMapContentCounters[itemId] ?? 0, counter)
        }
    }

    func hasMapContentVersion(itemId: UUID, contentVersion: Int?) -> Bool {
        guard let contentVersion else { return true }
        return mapContentVersions[itemId] == contentVersion
    }

    /// Starts one exact-version full-map repair. Repeated state/reference
    /// messages for the same missing generation are coalesced, while a later
    /// structural or asset generation can start its own repair.
    func beginMapRepair(
        itemId: UUID,
        assetVersion: Int?,
        contentVersion: Int?,
        presentsMap: Bool,
        counter: Int
    ) -> Bool {
        var repair = PendingMapRepair(
            assetVersion: assetVersion,
            contentVersion: contentVersion,
            presentsMap: presentsMap,
            counter: counter
        )
        if let pending = pendingMapRepairs[itemId],
           pending.assetVersion == assetVersion,
           pending.contentVersion == contentVersion {
            repair.presentsMap = pending.presentsMap || presentsMap
            repair.counter = max(pending.counter, counter)
            pendingMapRepairs[itemId] = repair
            return false
        }
        pendingMapRepairs[itemId] = repair
        pendingMapRequests.insert(itemId)
        return true
    }

    func beginMapBackgroundRepair(
        itemId: UUID,
        assetVersion: Int?,
        contentVersion: Int?,
        presentsMap: Bool,
        counter: Int
    ) -> Bool {
        var repair = PendingMapRepair(
            assetVersion: assetVersion,
            contentVersion: contentVersion,
            presentsMap: presentsMap || (pendingMapRepairs[itemId]?.presentsMap ?? false),
            counter: max(counter, pendingMapRepairs[itemId]?.counter ?? 0)
        )
        if let pending = pendingMapBackgroundRepairs[itemId],
           pending.assetVersion == assetVersion,
           pending.contentVersion == contentVersion {
            // The message counter is transport ordering, not part of the asset
            // generation. Keep the retry bounded when the same broken
            // generation is announced again under a newer counter.
            repair.presentsMap = pending.presentsMap || repair.presentsMap
            repair.counter = max(pending.counter, repair.counter)
            pendingMapBackgroundRepairs[itemId] = repair
            pendingMapRepairs[itemId] = repair
            return false
        }
        pendingMapBackgroundRepairs[itemId] = repair
        pendingMapRepairs[itemId] = repair
        pendingMapRequests.insert(itemId)
        return true
    }

    func pendingMapRepairMatches(_ data: NetworkCodableDataType) -> Bool {
        guard let repair = pendingMapRepairs[data.id] else { return true }
        if let assetVersion = repair.assetVersion,
           data.assetVersion != assetVersion {
            return false
        }
        if let contentVersion = repair.contentVersion,
           data.contentVersion != contentVersion {
            return false
        }
        return true
    }

    func pendingMapRepairRequirement(
        itemId: UUID
    ) -> (assetVersion: Int?, contentVersion: Int?, presentsMap: Bool, counter: Int)? {
        guard let repair = pendingMapRepairs[itemId] else { return nil }
        return (repair.assetVersion, repair.contentVersion, repair.presentsMap, repair.counter)
    }

    func supersedeMapRepair(itemId: UUID) {
        pendingMapRepairs[itemId] = nil
        pendingMapBackgroundRepairs[itemId] = nil
        pendingMapRequests.remove(itemId)
        pendingMapContentUpdates[itemId] = nil
        pendingMapStates[itemId] = nil
    }

    /// Completes an exact-version repair and returns whether that repair was
    /// attached to a presentation intent rather than background preloading.
    func completeMapRepair(itemId: UUID) -> Bool {
        let presentsMap = pendingMapRepairs[itemId]?.presentsMap ?? false
        pendingMapRepairs[itemId] = nil
        pendingMapBackgroundRepairs[itemId] = nil
        pendingMapRequests.remove(itemId)
        return presentsMap
    }

    func resetMapContentSequence() {
        pendingMapContentUpdates.removeAll()
        pendingMapStates.removeAll()
        lastMapContentUpdateCounters.removeAll()
        lastFullMapContentCounters.removeAll()
        lastMapStateCounters.removeAll()
        mapContentVersions.removeAll()
        pendingMapRepairs.removeAll()
        pendingMapBackgroundRepairs.removeAll()
        pendingMapRequests.removeAll()
        deferredMapPins.removeAll()
        deferredMapPinOrder.removeAll()
    }

    func reset(lostMaster: Bool) {
        self.lostMaster = lostMaster
    }
    
    func reset(sendPlayer: Bool) {
        self.hasSendPlayer = sendPlayer
    }
    
    func setGameUpdateType(_ type: NetworkModules) {
        gameUpdateType = type
    }
}

final class PlayerController: Sendable {
    // Strong on purpose: an intentional, temporary cycle GameRoot → GameModel →
    // PlayerController → GameRoot that stopGame() breaks by dropping the controllers.
    // `unowned` crashed here when in-flight controller tasks outlived
    // stopGame()/teardown. A strong reference keeps GameRoot alive until the
    // last task finishes.
    let root: GameRoot
    let gameModel: PlayerControllerModel
    let proxyMasterController: MasterController?
    let messagePipeline = GameMessagePipeline()
    
    @MainActor
    init(root: GameRoot, asGameMaster: Bool) {
        self.root = root
        self.gameModel = PlayerControllerModel()
        self.gameModel.asGameMaster = asGameMaster
        
        if asGameMaster {
            proxyMasterController = nil
            root.networkStore.setupLocal()
        } else {
            proxyMasterController = MasterController(root: root, asProxy: true)
        }
        root.networkStore.model.setPlayerDelegate(self)
        root.networkProxyStore.model.setProxyPlayerDelegate(self)
        Logger.networking.debug("PlayerController: Init")
    }
    
    deinit {
        Logger.networking.debug("PlayerController: Deinit")
    }
}

// MARK: - Control

extension PlayerController {
    @MainActor
    func start(to model: BrowserGameModel?) async -> Bool {
        Logger.networking.debug("PlayerController: Start")
        // Observers are a read-only local-network role. Do not let a nil Bonjour
        // target silently turn an observer into a SharePlay participant.
        if root.gameModel.gameType == .observer, model == nil {
            return false
        }
        if root.gameModel.gameType == .player {
            root.networkProxyStore.startProxyServer()
        } else if root.gameModel.gameType == .proxy {
            return await root.networkProxyStore.startPlayerGame(to: model)
        }
        return await root.networkStore.startPlayerGame(to: model)
    }
    
    @MainActor
    func stop() async {
        Logger.networking.debug("PlayerController: Stop")
        await messagePipeline.cancelAll()
        gameModel.sendCharacterTask?.cancel()
        gameModel.sendCharacterTask = nil
        gameModel.sendCharacterTaskId = nil
        gameModel.proxyFocusTask?.cancel()
        gameModel.proxyFocusTask = nil
        gameModel.proxyFocusTaskId = nil
        await root.networkProxyStore.stopGame()
        await root.networkStore.stopGame()
        await root.adventureRoot.adventureGameControllable.resetGame()
        gameModel.hasSendPlayer = false
        gameModel.pendingMapRequests = []
        gameModel.pendingAudioRequests = []
        gameModel.requestedRepairIds = []
        gameModel.requestedPdfRepairIds = []
        gameModel.requestedSpaceRepairIds = []
        gameModel.resetMasterStateSequence()
        gameModel.resetAudioListSequence()
        gameModel.resetPhotoListSequence()
        gameModel.resetPdfListSequence()
        gameModel.resetSpaceListSequence()
        gameModel.resetPresentationSequence()
        gameModel.resetMapContentSequence()
        gameModel.resetSharePlayMasterParticipant()
    }
    
    @MainActor
    func resetPlayers() {
        let players = root.gameModel.gameControl.controls.compactMap { $0.show ? $0.id : nil }
        root.audioRoot.gameControllable.gameModel.currentPlayers = (players + [root.gameModel.gameConfig.master.id]).sorted()
        root.photoRoot.gameControllable.gameModel.currentPlayers = (players + [root.gameModel.gameConfig.master.id]).sorted()
        root.pdfRoot.gameControllable.gameModel.currentPlayers = (players + [root.gameModel.gameConfig.master.id]).sorted()
        root.spaceRoot.gameControllable.gameModel.currentPlayers = (players + [root.gameModel.gameConfig.master.id]).sorted()
        root.tableRoot.gameControllable.gameModel.currentPlayers = (players + [root.gameModel.gameConfig.master.id]).sorted()
        root.weatherRoot.gameControllable.gameModel.currentPlayers = (players + [root.gameModel.gameConfig.master.id]).sorted()
        let playerNames = root.gameModel.gameControl.controls.map { $0.name }.sorted()
        root.diceRoot.diceGameControllable.resetPlayerDice(to: [root.gameModel.gameConfig.master.name] + playerNames)
    }
}

// MARK: - Send Messages

extension PlayerController {
    func send(updated: NetworkCodableDataType) async {
        guard await root.gameModel.gameType != .observer else { return }
        guard updated.type != .value else { return }
        await send(type: .store, subType: .store, updated: updated)
    }
    
    func game(message: NetworkCodableDataType, actionType: RPGMessageActionType) async {
        guard await root.gameModel.gameType != .observer else { return }
        // Players cannot publish Weather and Weather has no live updates yet.
        guard message.type != .table, message.type != .value, message.type != .weather else { return }
        if message.type == .photo, actionType == .generic {
            guard await root.gameModel.gameControl.features.photoSharing else { return }
            await sharePhoto(message)
            return
        }
        if message.type == .pdf, actionType == .generic {
            await sharePdf(message)
            return
        }
        if message.type == .space, actionType == .generic {
            await shareSpace(message)
            return
        }
        if message.type == .space, actionType == .spaceTransform {
            guard await root.gameModel.gameControl.features.spaceSharing else { return }
        }
        if message.type == .audio {
            guard await root.gameModel.gameControl.features.audioSharing else { return }
        }
        if message.type == .dice {
            guard await root.gameModel.gameControl.features.dicePlayers else { return }
        }
        await send(type: .update, subType: actionType, updated: message)
    }

    private func sharePhoto(_ fullData: NetworkCodableDataType) async {
        let (playerId, masterId) = await MainActor.run {
            (root.gameModel.gameConfig.id, root.gameModel.gameConfig.master.id)
        }
        let baseline = await root.photoRoot.photoGameControllable.masterVersion(
            for: fullData.id,
            masterId: masterId
        )
        let senderIsAvailable = await root.photoRoot.photoGameControllable.isPhotoAvailable(
            itemId: fullData.id,
            for: playerId,
            masterId: masterId
        )
        let matchesBaseline = baseline == fullData.effectiveAssetVersion

        let outgoing: NetworkCodableDataType
        if senderIsAvailable, matchesBaseline {
            let allPlayersHavePhoto = await root.photoRoot.gameControllable.allPlayersReported(for: fullData.id)
            outgoing = NetworkCodableDataType(
                id: fullData.id,
                type: fullData.type,
                version: fullData.version,
                data: allPlayersHavePhoto ? nil : fullData.data,
                assetVersion: fullData.assetVersion,
                contentVersion: fullData.contentVersion
            )
            if await root.photoRoot.gameControllable.setCurrent(itemId: fullData.id) {
                await MainActor.run { gameModel.gameUpdateType = .photo }
            }
        } else {
            // The master owns the canonical version. A player whose report is
            // absent or mismatched sends only that baseline reference; the
            // master answers by publishing its own bytes.
            outgoing = NetworkCodableDataType(
                id: fullData.id,
                type: fullData.type,
                version: baseline ?? fullData.effectiveAssetVersion
            )
        }

        await send(type: .reveal, subType: .show, updated: outgoing)

        if senderIsAvailable, matchesBaseline, outgoing.data != nil, let baseline {
            await root.photoRoot.photoGameControllable.markPhotoAvailableToCurrentPlayers(
                itemId: fullData.id,
                version: baseline,
                masterId: masterId
            )
        }
    }

    private func sharePdf(_ fullData: NetworkCodableDataType) async {
        let (playerId, masterId) = await MainActor.run {
            (root.gameModel.gameConfig.id, root.gameModel.gameConfig.master.id)
        }
        let baseline = await root.pdfRoot.pdfGameControllable.masterVersion(
            for: fullData.id,
            masterId: masterId
        )
        let senderIsAvailable = await root.pdfRoot.pdfGameControllable.isPdfAvailable(
            itemId: fullData.id,
            for: playerId,
            masterId: masterId
        )
        let matchesBaseline = baseline == fullData.effectiveAssetVersion

        let outgoing: NetworkCodableDataType
        if senderIsAvailable, matchesBaseline {
            let allPlayersHavePdf = await root.pdfRoot.gameControllable.allPlayersReported(for: fullData.id)
            outgoing = NetworkCodableDataType(
                id: fullData.id,
                type: fullData.type,
                version: fullData.version,
                data: allPlayersHavePdf ? nil : fullData.data,
                assetVersion: fullData.assetVersion,
                contentVersion: fullData.contentVersion
            )
            if await root.pdfRoot.gameControllable.setCurrent(itemId: fullData.id) {
                await MainActor.run { gameModel.gameUpdateType = .pdf }
            }
        } else {
            // The game master's file/version is canonical. A missing or stale
            // player report is a request for that asset, never an upload.
            outgoing = NetworkCodableDataType(
                id: fullData.id,
                type: fullData.type,
                version: baseline ?? fullData.effectiveAssetVersion
            )
        }

        await send(type: .reveal, subType: .show, updated: outgoing)

        if senderIsAvailable, matchesBaseline, outgoing.data != nil, let baseline {
            await root.pdfRoot.pdfGameControllable.markPdfAvailableToCurrentPlayers(
                itemId: fullData.id,
                version: baseline,
                masterId: masterId
            )
        }
    }

    private func shareSpace(_ fullData: NetworkCodableDataType) async {
        guard await root.gameModel.gameControl.features.spaceSharing else { return }
        let (playerId, masterId) = await MainActor.run {
            (root.gameModel.gameConfig.id, root.gameModel.gameConfig.master.id)
        }
        let baseline = await root.spaceRoot.spaceGameControllable.masterVersion(
            for: fullData.id,
            masterId: masterId
        )
        let senderIsAvailable = await root.spaceRoot.spaceGameControllable.isSpaceAvailable(
            itemId: fullData.id,
            for: playerId,
            masterId: masterId
        )
        let matchesBaseline = baseline == fullData.effectiveAssetVersion

        let outgoing: NetworkCodableDataType
        if senderIsAvailable, matchesBaseline {
            let allPlayersHaveSpace = await root.spaceRoot.gameControllable.allPlayersReported(for: fullData.id)
            outgoing = NetworkCodableDataType(
                id: fullData.id,
                type: fullData.type,
                version: fullData.version,
                data: allPlayersHaveSpace ? nil : fullData.data,
                assetVersion: fullData.assetVersion,
                contentVersion: fullData.contentVersion
            )
            if await root.spaceRoot.gameControllable.setCurrent(itemId: fullData.id) {
                await MainActor.run { gameModel.gameUpdateType = .space }
            }
        } else {
            // A peer never establishes a competing baseline. A missing or stale
            // report becomes a request for the game master's canonical asset.
            outgoing = NetworkCodableDataType(
                id: fullData.id,
                type: fullData.type,
                version: baseline ?? fullData.effectiveAssetVersion
            )
        }

        await send(type: .reveal, subType: .show, updated: outgoing)

        if senderIsAvailable, matchesBaseline, outgoing.data != nil, let baseline {
            await root.spaceRoot.spaceGameControllable.markSpaceAvailableToCurrentPlayers(
                itemId: fullData.id,
                version: baseline,
                masterId: masterId
            )
        }
    }
    
    func send(screen: AKImage, responseCounter: Int) async {
        let data = NetworkCodableDataType(id: UUID(), type: .game, version: 0, data: screen.jpegData(compressionQuality: 0.5))
        await send(counter: responseCounter, type: .store, subType: .screen, updated: data)
    }
    
    func send(
        counter: Int? = nil,
        type: RPGMessageType,
        subType: RPGMessageActionType = .show,
        updated: NetworkCodableDataType,
        useJournal: Bool = false,
        relayToProxyClients: Bool = true,
        purpose: GameMessagePurpose = .event
    ) async {
        // Tables have no live-update protocol. Only reveal/store messages may
        // carry their versioned canonical package.
        guard type != .update || updated.type != .table else { return }

        let outgoingTimestamp: TimeInterval
        if type == .update,
           subType == .spaceTransform,
           updated.type == .space {
            guard let timestamp = await root.spaceRoot.spaceGameControllable
                .causalSpaceTransformTimestamp(
                    itemId: updated.id,
                    version: updated.effectiveAssetVersion
                )
            else { return }
            outgoingTimestamp = timestamp
        } else {
            outgoingTimestamp = Date.now.timeIntervalSince1970
        }

        let outgoingCounter = await MainActor.run {
            counter ?? gameModel.nextOutgoingMessageCounter()
        }
        Logger.networking.debug("PlayerController: Send \(outgoingCounter, privacy: .public): \(type.debugDescription, privacy: .public) - \(subType.debugDescription, privacy: .public) for \(updated.id, privacy: .public)")
        let networtData = await MainActor.run {
            root.gameModel.outgoingMessage(
                timestamp: outgoingTimestamp,
                counter: outgoingCounter,
                type: type,
                subType: subType,
                asMaster: false,
                purpose: purpose,
                data: updated
            )
        }

        // Group transports do not echo a sender's own event, and the master no
        // longer republishes a canonical Space transform. Apply this exact
        // versioned envelope optimistically so SpaceViewer observes its own
        // timestamped transform as acknowledged and does not retry forever.
        if networtData.purpose == .event,
           networtData.type == .update,
           networtData.subType == .spaceTransform,
           networtData.data.type == .space {
            _ = await root.spaceRoot.spaceGameControllable.applySpaceTransform(
                data: networtData.data,
                counter: networtData.counter,
                timestamp: networtData.timestamp
            )
        }

        let origin: GameMessageOrigin = await root.gameModel.gameType == .proxy ? .proxy(nil) : .direct(nil)
        await root.statisticsModel.record(networtData, direction: .outgoing, origin: origin)

        let useOnTypeJournal = useJournal || Self.usesFileJournal(for: networtData)
        await sendOriginating(
            model: networtData,
            useJournal: useOnTypeJournal,
            relayToProxyClients: relayToProxyClients
        )
    }

    /// Turns one private mirror's presentation into one canonical host-player
    /// event. The same remapped envelope is used for the upstream send, sibling
    /// mirrors, and the co-located host player so transport retries cannot mint
    /// independent counters or identities for a single user gesture.
    func relayProxyPresentation(
        _ source: GameNetworkModel,
        excludingProxyConnection connectionId: ConnectionController.ID?
    ) async {
        guard source.purpose == .event,
              source.type == .reveal,
              source.subType == .show,
              (source.data.type == .photo || source.data.type == .pdf || source.data.type == .space)
        else { return }

        let outgoingCounter = await MainActor.run {
            gameModel.nextOutgoingMessageCounter()
        }
        let remapped = await MainActor.run {
            root.gameModel.outgoingMessage(
                timestamp: source.timestamp,
                counter: outgoingCounter,
                type: source.type,
                subType: source.subType,
                asMaster: false,
                purpose: source.purpose,
                data: source.data
            )
        }

        Logger.networking.debug("PlayerController: Relay proxy presentation \(outgoingCounter, privacy: .public) for \(source.data.type.token, privacy: .public) -> \(source.data.id, privacy: .public)")
        await root.statisticsModel.record(remapped, direction: .outgoing, origin: .proxy(connectionId))

        // Upstream exactly once. In particular, local application below must
        // never manufacture an acknowledgement or repair request of its own.
        await root.networkStore.sendMaster(
            data: remapped,
            fileJournal: Self.usesFileJournal(for: remapped)
        )

        // A private mirror cannot establish a new asset generation. Apply the
        // optimistic local presentation only when it matches the authoritative
        // master baseline; otherwise the master's canonical response will drive
        // the host and mirrors in the regular path.
        guard await canApplyRemappedProxyPresentation(remapped) else { return }
        await receivedProcess(remapped, origin: .local)
        if let connectionId {
            await root.networkProxyStore.sendPlayer(data: remapped, except: connectionId)
        } else {
            await root.networkProxyStore.sendPlayer(data: remapped)
        }
    }

    /// Remaps a private mirror's small group event to the host identity once,
    /// then sends that same envelope upstream and to sibling mirrors. The host
    /// controller has already applied the event locally.
    func relayProxyGroupEvent(
        _ source: GameNetworkModel,
        excludingProxyConnection connectionId: ConnectionController.ID?
    ) async {
        let isSupportedEvent = source.isDiceRollEvent ||
            (source.purpose == .event &&
             source.type == .update &&
             ((source.subType == .mapPin && source.data.type == .map) ||
              (source.subType == .spaceTransform && source.data.type == .space)))
        guard isSupportedEvent else { return }

        let outgoingCounter = await MainActor.run {
            gameModel.nextOutgoingMessageCounter()
        }
        let remapped = await MainActor.run {
            root.gameModel.outgoingMessage(
                timestamp: source.timestamp,
                counter: outgoingCounter,
                type: source.type,
                subType: source.subType,
                asMaster: false,
                purpose: source.purpose,
                data: source.data
            )
        }
        await root.statisticsModel.record(
            remapped,
            direction: .outgoing,
            origin: .proxy(connectionId)
        )
        await root.networkStore.sendMaster(data: remapped, fileJournal: false)
        if let connectionId {
            await root.networkProxyStore.sendPlayer(data: remapped, except: connectionId)
        } else {
            await root.networkProxyStore.sendPlayer(data: remapped)
        }
    }

    private func canApplyRemappedProxyPresentation(_ model: GameNetworkModel) async -> Bool {
        let masterId = await root.gameModel.gameConfig.master.id
        let version = model.data.effectiveAssetVersion

        switch model.data.type {
        case .photo:
            guard await root.gameModel.gameControl.features.photoSharing else { return false }
            return await root.photoRoot.photoGameControllable.masterVersion(
                for: model.data.id,
                masterId: masterId
            ) == version
        case .pdf:
            return await root.pdfRoot.pdfGameControllable.masterVersion(
                for: model.data.id,
                masterId: masterId
            ) == version
        case .space:
            guard await root.gameModel.gameControl.features.spaceSharing else { return false }
            return await root.spaceRoot.spaceGameControllable.masterVersion(
                for: model.data.id,
                masterId: masterId
            ) == version
        default:
            return false
        }
    }

    static func usesFileJournal(for model: GameNetworkModel) -> Bool {
        model.usesFileJournal || usesFileJournal(type: model.type, subType: model.subType, data: model.data)
    }

    static func usesFileJournal(for data: NetworkCodableDataType) -> Bool {
        data.usesFileJournal
    }

    static func usesFileJournal(type: RPGMessageType, subType: RPGMessageActionType, data: NetworkCodableDataType) -> Bool {
        type == .update && subType == .generic && data.type == .audio && data.data != nil
    }

    static func shouldStartAudioPlayback(isSharePlayActive: Bool, asGameMaster: Bool) -> Bool {
        !isSharePlayActive || asGameMaster
    }
    
    private func sendOriginating(
        model: GameNetworkModel,
        useJournal: Bool = false,
        relayToProxyClients: Bool = true
    ) async {
        if await root.gameModel.gameType == .proxy {
            await root.networkProxyStore.sendMaster(data: model)
        } else {
            await root.networkStore.sendMaster(data: model, fileJournal: useJournal)
            if relayToProxyClients, model.effectiveAudience == .group {
                await root.networkProxyStore.sendPlayer(data: model)
            }
        }
    }

    private func sendUpstream(model: GameNetworkModel) async {
        if await root.gameModel.gameType == .proxy {
            await root.networkProxyStore.sendMaster(data: model)
        } else {
            await root.networkStore.sendMaster(data: model, fileJournal: false)
        }
    }
}

// MARK: - Send PlayerNetworkStoreDelegate

extension PlayerController: PlayerNetworkStoreDelegate {
    func lostConnection() async {
        await resetForLostConnection(preservingSharePlayRebind: false)
    }

    func sharePlayParticipantLeft(id: UUID) async {
        guard await gameModel.removeSharePlayMasterParticipant(id: id) else { return }
        await resetForLostConnection(preservingSharePlayRebind: true)
    }

    private func resetForLostConnection(
        preservingSharePlayRebind: Bool
    ) async {
        Logger.networking.debug("PlayerController: Lost Connection - Reset State")
        await MainActor.run {
            gameModel.sendCharacterTask?.cancel()
            gameModel.sendCharacterTask = nil
            gameModel.sendCharacterTaskId = nil
            gameModel.pendingMapRequests = []
            gameModel.pendingAudioRequests = []
            gameModel.requestedRepairIds = []
            gameModel.requestedPdfRepairIds = []
            gameModel.requestedSpaceRepairIds = []
            gameModel.resetMasterStateSequence()
            gameModel.resetAudioListSequence()
            gameModel.resetPhotoListSequence()
            gameModel.resetPdfListSequence()
            gameModel.resetSpaceListSequence()
            gameModel.resetPresentationSequence()
            gameModel.resetMapContentSequence()
            if !preservingSharePlayRebind {
                gameModel.resetSharePlayMasterParticipant()
            }
        }
        await root.spaceRoot.spaceGameControllable.resetSpaceTransforms()
        await gameModel.reset(lostMaster: true)
        await gameModel.reset(sendPlayer: false)
    }
    
    func ready() async {
        Logger.networking.debug("PlayerController: Ready")
        await gameModel.reset(lostMaster: false)
        await sendAudioList()
        await sendPhotoList()
        await sendPdfList()
        await sendSpaceList()
        await scheduleSendCharacter()
    }
    
    func receivedFile(_ model: GameNetworkModel) async {
        Logger.networking.debug("PlayerController: FILE Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
        let receivesOppositeRole = await root.gameModel.gameConfig.isMaster != model.sender.isMaster
        // A player-authored file presentation has already been authenticated by
        // GameNetworkController before it reaches this callback. LAN and
        // SharePlay both fan that group event out to sibling players, so equal
        // player roles are expected here; all other same-role file traffic is
        // still rejected.
        guard receivesOppositeRole || model.isPlayerFilePresentationEvent else { return }
        await receivedProcess(model, origin: .file)
    }
    
    func received(_ model: GameNetworkModel) async {
        await receivedProcess(model, fromProxy: false)
    }

    func receivedSharePlay(_ model: GameNetworkModel, participantId: UUID) async {
        await receivedProcess(model, origin: .sharePlay(participantId))
    }

    func acceptsSharePlayPeerMessage(
        _ model: GameNetworkModel,
        participantId: UUID
    ) async -> Bool {
        guard model.sender.role == .player,
              model.effectiveAudience == .group,
              GameNetworkModel.acceptsEventTimestamp(model.timestamp),
              await acceptsSessionMessage(
                  model,
                  origin: .sharePlay(participantId)
              )
        else { return false }

        // The master-authored roster is the logical identity authority on a
        // player-only device. Validate it before GameNetworkController commits
        // the physical participant binding, preventing an unknown or wrong-role
        // first packet from poisoning that immutable transport identity.
        return await root.gameModel.gameRoster.players.contains {
            $0.id == model.sender.id && $0.type == .player
        }
    }

    func shouldDeferSharePlayPeerGroupEvent(
        _ model: GameNetworkModel,
        participantId: UUID
    ) async -> Bool {
        guard model.isDeferrablePlayerGroupEvent,
              await acceptsSessionMessage(
                  model,
                  origin: .sharePlay(participantId)
              )
        else { return false }

        // An existing non-player roster entry is an authoritative rejection,
        // not an ordering race. Only an entirely absent identity gets one
        // opportunity to wait for the next master roster update.
        return await !root.gameModel.gameRoster.players.contains {
            $0.id == model.sender.id
        }
    }

    func didAcceptSharePlayMasterState(
        _ model: GameNetworkModel,
        participantId: UUID
    ) async -> Bool {
        guard model.sender.isMaster,
              model.sender.id == model.masterId,
              model.masterState != nil,
              await gameModel.isSharePlayMasterParticipant(id: participantId),
              await root.gameModel.gameConfig.master.id == model.masterId
        else { return false }

        return await gameModel.hasAppliedMasterState(
            from: model.masterId,
            counter: model.counter
        )
    }

    func acceptsSharePlayMasterJournalAdmission(
        _ model: GameNetworkModel,
        participantId: UUID
    ) async -> Bool {
        guard model.isMasterJournalAdmissionMetadata else { return false }
        return await acceptsSessionMessage(
            model,
            origin: .sharePlay(participantId)
        )
    }

    func isLocalSharePlayTarget(_ targetId: UUID?) async -> Bool {
        guard let targetId else { return true }
        return await root.gameModel.gameConfig.id == targetId
    }

    func receivedSharePlayFile(_ model: GameNetworkModel) async {
        let receivesOppositeRole = await root.gameModel.gameConfig.isMaster != model.sender.isMaster
        guard receivesOppositeRole || model.isPlayerFilePresentationEvent else { return }
        await receivedProcess(model, origin: .file)
    }

    func isPinnedSharePlayMasterParticipant(id: UUID) async -> Bool {
        await gameModel.isSharePlayMasterParticipant(id: id)
    }

    func sharePlayFileLoadFailed(_ model: GameNetworkModel) async {
        guard model.sender.isMaster,
              await !root.gameModel.gameConfig.isMaster,
              await acceptsSessionMessage(model, origin: .file)
        else { return }

        if model.type == .reveal {
            // A reveal reference may be fully satisfied by an exact-version
            // local item. The regular handler ACKs that case and requests bytes
            // only when the item or its backing file is unavailable.
            await receivedProcess(model, origin: .file)
            return
        }

        // Metadata-only stores and journaled updates do not consistently ask
        // for missing bytes. Convert the recovery into a store request; the
        // master rebuilds the full module payload and targets its reply here.
        var requestTrigger = model
        requestTrigger.type = .store
        requestTrigger.subType = .store
        let request = await response(for: requestTrigger, isSuccess: true, requestData: true)
        await sendUpstream(model: request)
    }
    
    func receivedProcess(_ model: GameNetworkModel, fromProxy: Bool = false) async {
        Logger.networking.debug("PlayerController: Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")

        let origin: GameMessageOrigin = fromProxy ? .proxy(nil) : .direct(nil)
        await receivedProcess(model, origin: origin)
    }

    private func receivedProcess(_ model: GameNetworkModel, origin: GameMessageOrigin) async {
        // Admission-only metadata is consumed by GameNetworkController after
        // physical SharePlay attribution. It is never a gameplay message.
        guard !model.isJournalAdmissionOnly else { return }
        guard await acceptsSessionMessage(model, origin: origin) else {
            Logger.networking.debug("PlayerController: Message rejected because its sender does not belong to this game session")
            return
        }
        guard await messagePipeline.enqueue(GameMessageEvent(model: model, origin: origin)) else {
            Logger.networking.debug("PlayerController: Duplicate ignored \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public)")
            return
        }
        await processMessages()
    }

    /// Establishes authority from the first complete master broadcast and then
    /// pins every remote envelope to that session. A locally remapped proxy
    /// presentation is already authenticated by the proxy host controller.
    private func acceptsSessionMessage(
        _ model: GameNetworkModel,
        origin: GameMessageOrigin
    ) async -> Bool {
        let config = await root.gameModel.gameConfig
        let acceptsLogicalAuthority: Bool

        if origin == .local {
            acceptsLogicalAuthority = model.masterId == config.master.id
        } else if config.master.type == .master {
            guard model.masterId == config.master.id else { return false }
            if model.sender.isMaster {
                acceptsLogicalAuthority = model.sender.id == config.master.id
            } else {
                acceptsLogicalAuthority = model.sender.id != config.master.id &&
                    model.masterState == nil
            }
        } else {
            // Before discovery, only a self-consistent full master broadcast may
            // establish the authoritative master UUID. Player-to-player traffic
            // cannot race that first message and nominate a different session.
            acceptsLogicalAuthority = model.sender.isMaster &&
                model.sender.id == model.masterId &&
                model.masterState != nil
        }

        guard acceptsLogicalAuthority else { return false }
        guard model.sender.isMaster,
              case let .sharePlay(participantId) = origin
        else { return true }

        // Messenger exposes the physical source participant. Pin that source
        // as well as the logical master UUID so another peer cannot copy the
        // public master identity into a forged envelope. Journal callbacks do
        // not expose a publisher and therefore remain logically authenticated.
        switch await gameModel.acceptSharePlayMasterParticipant(
            id: participantId,
            isCompleteMasterBroadcast: model.masterState != nil
        ) {
        case .newlyBound, .alreadyBound:
            return true
        case .rebound:
            // The GroupSession can survive while the master's participant ID
            // changes. Re-announce availability and Character exactly as on a
            // fresh session so the rejoined master rebuilds its reports.
            await ready()
            return true
        case .rejected:
            return false
        }
    }

    private func isRemappedProxyPresentation(_ event: GameMessageEvent) -> Bool {
        let model = event.model
        guard event.origin == .local || event.fromProxy else { return false }
        return model.isPlayerFilePresentationEvent
    }

    private func prepareForProcessing(_ event: GameMessageEvent) async -> Bool {
        let model = event.model

        // Targeted messages are only processed by the addressee. Proxy clients
        // are deliberately invisible upstream and every proxy request is remapped
        // to its host ID, so a target belonging to another host can never live
        // behind this device.
        if let targetId = model.targetId, await targetId != root.gameModel.gameConfig.id {
            Logger.networking.debug("PlayerController: Message ignored, targeted at \(targetId, privacy: .public)")
            return false
        }

        if await !gameModel.asGameMaster {
            let controls = if let authoritativeControls = model.masterState?.controls {
                authoritativeControls
            } else {
                await root.gameModel.gameControl.controls
            }
            if let masterState = model.masterState,
               model.sender.isMaster,
               await gameModel.shouldApplyMasterState(from: model.masterId, counter: model.counter) {
                // One MainActor hop for the whole broadcast: applying config,
                // controls and roster in separate steps lets concurrent message
                // builders capture a torn state and send it back to the master.
                await MainActor.run {
                    root.gameModel.applyMasterBroadcast(masterId: model.masterId, masterName: model.sender.name, state: masterState)
                    resetPlayers()
                }
            }

            let localId = await root.gameModel.gameConfig.id
            let type = await root.gameModel.gameType
            let photoSharing = await root.gameModel.gameControl.features.photoSharing
            let spaceSharing = await root.gameModel.gameControl.features.spaceSharing
            let dicePlayers = await root.gameModel.gameControl.features.dicePlayers
            guard type == .proxy || type == .observer || controls.isEmpty || controls.contains(where: { $0.id == localId && $0.show == true }) else {
                Logger.networking.debug("PlayerController: Message will be ignored because of controls \(controls, privacy: .public)")
                return false
            }
            // SharePlay physically broadcasts player-to-master repair requests.
            // Reject them before any module handler; only genuine player group
            // events may use the peer-to-peer presentation path.
            if !model.sender.isMaster, model.effectiveAudience == .master {
                Logger.networking.debug("PlayerController: Master-only player message ignored")
                return false
            }
            let acceptsPlayerPhotoReveal = model.isPlayerFilePresentationEvent &&
                model.data.type == .photo &&
                photoSharing
            let acceptsPlayerPdfReveal = model.isPlayerFilePresentationEvent &&
                model.data.type == .pdf
            let acceptsPlayerSpaceReveal = model.isPlayerFilePresentationEvent &&
                model.data.type == .space &&
                spaceSharing
            let acceptsPlayerDice = model.isPlayerDiceGroupEvent &&
                dicePlayers &&
                model.effectiveAudience == .group
            let acceptsPlayerMapPin = model.sender.role == .player &&
                model.type == .update &&
                model.subType == .mapPin &&
                model.data.type == .map &&
                model.effectiveAudience == .group
            let acceptsPlayerSpaceTransform = model.sender.role == .player &&
                model.type == .update &&
                model.subType == .spaceTransform &&
                model.data.type == .space &&
                spaceSharing &&
                model.effectiveAudience == .group
            guard await root.gameModel.gameType == .proxy || model.sender.isMaster || acceptsPlayerDice || acceptsPlayerPhotoReveal || acceptsPlayerPdfReveal || acceptsPlayerSpaceReveal || acceptsPlayerMapPin || acceptsPlayerSpaceTransform else {
                Logger.networking.debug("PlayerController: Message will be ignored because it is send from Player \(model.senderName, privacy: .public)")
                return false
            }
        }

        // Value messages synchronize the joining player's Character and are
        // not part of the presentation ordering state machine.
        if model.data.type != .value,
           (model.isPresentationIntent || model.isMapPresentationRepair) {
            let presentationVersion: Int
            let allowsUnversionedMapState: Bool
            if model.data.type == .map,
               model.type == .update,
               model.subType == .mapState {
                // Live state belongs to the currently intended Map asset. New
                // peers include the asset fingerprint; legacy peers are allowed
                // to repair the same item with an unversioned state only.
                presentationVersion = model.data.assetVersion ?? 0
                allowsUnversionedMapState = model.data.assetVersion == nil
            } else if model.data.type == .map {
                // The legacy MapModel.version covers scales only. The background
                // asset fingerprint is the presentation generation that must
                // reject a delayed Journal attachment for an older background.
                presentationVersion = model.data.effectiveAssetVersion
                allowsUnversionedMapState = false
            } else {
                presentationVersion = model.data.version
                allowsUnversionedMapState = false
            }
            let shouldProcess = await gameModel.shouldProcessPresentation(
                from: model.masterId,
                senderID: model.sender.id,
                module: model.data.type,
                itemId: model.data.id,
                version: presentationVersion,
                counter: model.counter,
                timestamp: model.timestamp,
                isRepair: model.targetId != nil || model.isMapPresentationRepair,
                allowsUnversionedStateRepair: model.isTargetedMapStatePresentationRepair || allowsUnversionedMapState
            )
            guard shouldProcess else {
                Logger.networking.debug("PlayerController: Stale presentation ignored \(model.counter, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
                return false
            }
        }

        if !event.fromProxy, event.origin != .local, !model.isAcknowledgement {
            if model.data.type != .value {
                // Proxy clients mirror this player: an answer addressed to this
                // device must be processed by them too, so clear the target before
                // forwarding. Messages targeted at other hosts were already
                // rejected above and never reach this point. Character bootstrap bypasses
                // this path and is sent directly by the proxy master controller.
                var forwarded = model
                if await forwarded.targetId == root.gameModel.gameConfig.id {
                    forwarded.targetId = nil
                }
                await root.networkProxyStore.sendPlayer(data: forwarded)
            }
            await scheduleSendCharacter()
        }
        return true
    }
    
    func processMessages() async {
        while let event = await messagePipeline.next() {
            guard await prepareForProcessing(event) else {
                await messagePipeline.processed(success: true)
                continue
            }

            do {
                try Task.checkCancellation()
                let response = try await handle(
                    event.model,
                    usesSharePlayPlaybackCoordination: event.origin.usesSharePlayFileTransport,
                    locallyMirroredProxyPresentation: isRemappedProxyPresentation(event)
                )
                try Task.checkCancellation()
                if let response, event.origin != .local {
                    await sendUpstream(model: response)
                    if response.subType == .ok {
                        await gameModel.increaseMessageCounter()
                    }
                } else {
                    await gameModel.increaseMessageCounter()
                }
                await root.statisticsModel.record(
                    event.model,
                    direction: .incoming,
                    origin: event.origin
                )
                await messagePipeline.processed(success: true)
            } catch is CancellationError {
                await messagePipeline.processed(success: false)
                return
            } catch {
                Logger.networking.error("PlayerController: Failed to process \(event.model.debugDescription, privacy: .public): \(error.localizedDescription, privacy: .public)")
                if event.origin != .local {
                    let failure = await response(for: event.model, isSuccess: false, requestData: false)
                    await sendUpstream(model: failure)
                }
                await messagePipeline.processed(success: false)
            }
        }
    }
}

// MARK: - Send PlayerNetworkProxyStoreDelegate

extension PlayerController: PlayerNetworkProxyControllerDelegate {
    func lostProxyConnection() async {
        Logger.networking.debug("PlayerController: Lost Proxy Connection - Reset State")
        await lostConnection()
    }
    
    func readyProxy() async {
        Logger.networking.debug("PlayerController: Proxy Ready")
        await gameModel.reset(lostMaster: false)
        await sendAudioList()
        await sendPhotoList()
        await sendPdfList()
        await sendSpaceList()
        await scheduleSendCharacter()
    }
    
    func receivedProxy(_ model: GameNetworkModel) async {
        Logger.networking.debug("PlayerController: Proxy Received \(model.counter, privacy: .public) / \(model.proxyCounter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
        await receivedProcess(model, fromProxy: true)
    }
}

extension PlayerController {
    func handle(
        _ model: GameNetworkModel,
        usesSharePlayPlaybackCoordination: Bool = false,
        locallyMirroredProxyPresentation: Bool = false
    ) async throws -> GameNetworkModel? {
        switch model.data.type {
        case .none, .game, .setting, .editor, .generator, .search:
            return nil
        case .adventure:
            return handleAdventure(model)
        case .audio:
            return try await handleAudio(
                model,
                usesSharePlayPlaybackCoordination: usesSharePlayPlaybackCoordination
            )
        case .dice:
            return try await handleDice(model)
        case .pdf:
            return try await handlePdf(
                model,
                locallyMirroredProxyPresentation: locallyMirroredProxyPresentation
            )
        case .photo:
            return try await handlePhoto(
                model,
                locallyMirroredProxyPresentation: locallyMirroredProxyPresentation
            )
        case .map:
            return try await handleMap(model)
        case .table:
            return try await handleTable(model)
        case .weather:
            return try await handleWeather(model)
        case .value:
            return try await handleValue(model)
        case .space:
            return try await handleSpace(
                model,
                locallyMirroredProxyPresentation: locallyMirroredProxyPresentation
            )
        @unknown default:
            fatalError()
        }
    }
    
    func handleAdventure(_ model: GameNetworkModel) -> GameNetworkModel? {
        nil
    }
    
    func handleAudio(
        _ model: GameNetworkModel,
        usesSharePlayPlaybackCoordination: Bool = false
    ) async throws -> GameNetworkModel? {
        if model.subType == .ok {
            await root.audioRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            return nil
        }
        guard model.subType != .failed else { return nil }
        
        switch model.type {
        case .reveal:
            let revealed = try await root.audioRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true)
            if revealed, await root.audioRoot.audioGameControllable.hasLocalAudioData(for: model.data.id) {
                await MainActor.run { _ = gameModel.pendingAudioRequests.remove(model.data.id) }
                await root.audioRoot.audioGameControllable.applyAudio(id: model.data.id, for: [root.gameModel.gameConfig.id, model.sender.id])
                return await response(for: model, isSuccess: true, requestData: false)
            } else {
                await MainActor.run { _ = gameModel.pendingAudioRequests.insert(model.data.id) }
                return await response(for: model, isSuccess: true, requestData: true)
            }
        case .store:
            try await root.audioRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
            guard await root.audioRoot.audioGameControllable.hasLocalAudioData(for: model.data.id) else {
                await MainActor.run { _ = gameModel.pendingAudioRequests.insert(model.data.id) }
                return await response(for: model, isSuccess: true, requestData: true)
            }
            let completesReveal = await MainActor.run { gameModel.pendingAudioRequests.remove(model.data.id) != nil }
            if completesReveal {
                _ = await root.audioRoot.gameControllable.setCurrent(itemId: model.data.id)
            }
            await root.audioRoot.audioGameControllable.applyAudio(id: model.data.id, for: [root.gameModel.gameConfig.id, model.sender.id])
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            switch model.subType {
            case .audioList:
                _ = await applyAudioList(model)
            case .playAudio:
                guard model.sender.isMaster else { return nil }
                if await root.audioRoot.audioGameControllable.shouldPlay(with: model.data) {
                    await reportAudioAvailableToCurrentPlayers(itemId: model.data.id, model: model)
                }
                let asGameMaster = await gameModel.asGameMaster
                if Self.shouldStartAudioPlayback(
                    isSharePlayActive: usesSharePlayPlaybackCoordination,
                    asGameMaster: asGameMaster
                ) {
                    let _ = await root.audioRoot.audioGameControllable.play(with: model.data).result
                } else {
                    // The master device initiates playback; other SharePlay
                    // participants only prepare for AVPlayerPlaybackCoordinator.
                    await root.audioRoot.audioGameControllable.loadPlaylist(id: model.data.id)
                }
            default:
                break
            }
        }
        return nil
    }

    @MainActor
    private func applyAudioList(_ model: GameNetworkModel) -> Bool {
        guard model.sender.isMaster,
              gameModel.canApplyAudioList(from: model.masterId, counter: model.counter),
              root.audioRoot.audioGameControllable.applyAudioList(
                  data: model.data,
                  for: model.masterId,
                  authoritative: true
              )
        else { return false }

        gameModel.recordAudioList(counter: model.counter, from: model.masterId)
        return true
    }

    @MainActor
    private func applyPhotoList(_ model: GameNetworkModel) async -> Bool {
        guard model.sender.isMaster,
              gameModel.canApplyPhotoList(from: model.masterId, counter: model.counter),
              await root.photoRoot.photoGameControllable.applyPhotoList(
                  data: model.data,
                  for: model.masterId,
                  with: model.masterId,
                  authoritative: true
              )
        else { return false }

        gameModel.recordPhotoList(counter: model.counter, from: model.masterId)
        return true
    }

    private func playerPhotoRevealValidation(for model: GameNetworkModel) async -> PlayerPhotoRevealValidation {
        if await gameModel.asGameMaster {
            let senderIsAvailable = await root.photoRoot.photoGameControllable.isPhotoAvailable(
                itemId: model.data.id,
                for: model.sender.id,
                masterId: model.masterId
            )
            let baseline = await root.photoRoot.photoGameControllable.masterVersion(
                for: model.data.id,
                masterId: model.masterId
            )
            return senderIsAvailable && baseline == model.data.effectiveAssetVersion ? .valid : .mismatch
        }

        guard await gameModel.hasAuthoritativePhotoList(from: model.masterId) else {
            return .awaitingAuthoritativeList
        }

        guard let senderVersion = await root.photoRoot.photoGameControllable.reportedVersion(
            for: model.data.id,
            playerId: model.sender.id
        ) else {
            // Another player's report may simply not have reached the master
            // when this authoritative snapshot was broadcast.
            return .awaitingAuthoritativeList
        }

        guard senderVersion == model.data.effectiveAssetVersion else {
            return .mismatch
        }
        guard let baseline = await root.photoRoot.photoGameControllable.masterVersion(
            for: model.data.id,
            masterId: model.masterId
        ) else {
            return .awaitingAuthoritativeList
        }
        return senderVersion == baseline ? .valid : .mismatch
    }

    private func retryDeferredPhotoReveals(from masterId: UUID) async {
        let deferred = await gameModel.deferredPhotoReveals(from: masterId)
        for model in deferred {
            switch await playerPhotoRevealValidation(for: model) {
            case .awaitingAuthoritativeList:
                continue
            case .mismatch:
                await gameModel.removeDeferredPhotoReveal(model)
            case .valid:
                await gameModel.removeDeferredPhotoReveal(model)
                guard await deferredPresentationIsCurrent(model) else { continue }
                do {
                    if let response = try await handlePhoto(model) {
                        await sendUpstream(model: response)
                    }
                } catch {
                    // The original network event was already accepted. A bad
                    // deferred payload must not make the photo-list update fail.
                    Logger.networking.error("PlayerController: Deferred photo reveal failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    @MainActor
    private func applyPdfList(_ model: GameNetworkModel) async -> Bool {
        guard model.sender.isMaster,
              gameModel.canApplyPdfList(from: model.masterId, counter: model.counter),
              await root.pdfRoot.pdfGameControllable.applyPdfList(
                  data: model.data,
                  for: model.masterId,
                  with: model.masterId,
                  authoritative: true
              )
        else { return false }

        gameModel.recordPdfList(counter: model.counter, from: model.masterId)
        return true
    }

    private func playerPdfRevealValidation(for model: GameNetworkModel) async -> PlayerPdfRevealValidation {
        if await gameModel.asGameMaster {
            let senderIsAvailable = await root.pdfRoot.pdfGameControllable.isPdfAvailable(
                itemId: model.data.id,
                for: model.sender.id,
                masterId: model.masterId
            )
            let baseline = await root.pdfRoot.pdfGameControllable.masterVersion(
                for: model.data.id,
                masterId: model.masterId
            )
            return senderIsAvailable && baseline == model.data.effectiveAssetVersion ? .valid : .mismatch
        }

        guard await gameModel.hasAuthoritativePdfList(from: model.masterId) else {
            return .awaitingAuthoritativeList
        }
        guard let senderVersion = await root.pdfRoot.pdfGameControllable.reportedVersion(
            for: model.data.id,
            playerId: model.sender.id
        ) else {
            return .awaitingAuthoritativeList
        }
        guard senderVersion == model.data.effectiveAssetVersion else {
            return .mismatch
        }
        guard let baseline = await root.pdfRoot.pdfGameControllable.masterVersion(
            for: model.data.id,
            masterId: model.masterId
        ) else {
            return .awaitingAuthoritativeList
        }
        return senderVersion == baseline ? .valid : .mismatch
    }

    private func retryDeferredPdfReveals(from masterId: UUID) async {
        let deferred = await gameModel.deferredPdfReveals(from: masterId)
        for model in deferred {
            switch await playerPdfRevealValidation(for: model) {
            case .awaitingAuthoritativeList:
                continue
            case .mismatch:
                await gameModel.removeDeferredPdfReveal(model)
            case .valid:
                await gameModel.removeDeferredPdfReveal(model)
                guard await deferredPresentationIsCurrent(model) else { continue }
                do {
                    if let response = try await handlePdf(model) {
                        await sendUpstream(model: response)
                    }
                } catch {
                    Logger.networking.error("PlayerController: Deferred PDF reveal failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    @MainActor
    private func applySpaceList(_ model: GameNetworkModel) async -> Bool {
        guard model.sender.isMaster,
              gameModel.canApplySpaceList(from: model.masterId, counter: model.counter),
              await root.spaceRoot.spaceGameControllable.applySpaceList(
                  data: model.data,
                  for: model.masterId,
                  with: model.masterId,
                  authoritative: true
              )
        else { return false }

        gameModel.recordSpaceList(counter: model.counter, from: model.masterId)
        return true
    }

    private func playerSpaceRevealValidation(for model: GameNetworkModel) async -> PlayerSpaceRevealValidation {
        if await gameModel.asGameMaster {
            let senderIsAvailable = await root.spaceRoot.spaceGameControllable.isSpaceAvailable(
                itemId: model.data.id,
                for: model.sender.id,
                masterId: model.masterId
            )
            let baseline = await root.spaceRoot.spaceGameControllable.masterVersion(
                for: model.data.id,
                masterId: model.masterId
            )
            return senderIsAvailable && baseline == model.data.effectiveAssetVersion ? .valid : .mismatch
        }

        guard await gameModel.hasAuthoritativeSpaceList(from: model.masterId) else {
            return .awaitingAuthoritativeList
        }
        guard let senderVersion = await root.spaceRoot.spaceGameControllable.reportedVersion(
            for: model.data.id,
            playerId: model.sender.id
        ) else {
            return .awaitingAuthoritativeList
        }
        guard senderVersion == model.data.effectiveAssetVersion else {
            return .mismatch
        }
        guard let baseline = await root.spaceRoot.spaceGameControllable.masterVersion(
            for: model.data.id,
            masterId: model.masterId
        ) else {
            return .awaitingAuthoritativeList
        }
        return senderVersion == baseline ? .valid : .mismatch
    }

    private func retryDeferredSpaceReveals(from masterId: UUID) async {
        let deferred = await gameModel.deferredSpaceReveals(from: masterId)
        for model in deferred {
            switch await playerSpaceRevealValidation(for: model) {
            case .awaitingAuthoritativeList:
                continue
            case .mismatch:
                await gameModel.removeDeferredSpaceReveal(model)
            case .valid:
                await gameModel.removeDeferredSpaceReveal(model)
                guard await deferredPresentationIsCurrent(model) else { continue }
                do {
                    if let response = try await handleSpace(model) {
                        await sendUpstream(model: response)
                    }
                } catch {
                    // The list itself is valid. A bad deferred file must not make
                    // availability sequencing fail or reserve a later counter.
                    Logger.networking.error("PlayerController: Deferred Space reveal failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func playerSpaceTransformValidation(
        for model: GameNetworkModel
    ) async -> PlayerSpaceTransformValidation {
        guard await root.gameModel.gameControl.features.spaceSharing else {
            return .mismatch
        }
        if await !gameModel.asGameMaster,
           await !gameModel.hasAuthoritativeSpaceList(from: model.masterId) {
            return .awaitingAuthoritativeList
        }
        guard let baseline = await root.spaceRoot.spaceGameControllable.masterVersion(
            for: model.data.id,
            masterId: model.masterId
        ) else {
            return .awaitingAuthoritativeList
        }
        guard baseline == model.data.effectiveAssetVersion else {
            return .mismatch
        }
        guard let senderVersion = await root.spaceRoot.spaceGameControllable.reportedVersion(
            for: model.data.id,
            playerId: model.sender.id
        ) else {
            return .awaitingAuthoritativeList
        }
        return senderVersion == baseline ? .valid : .mismatch
    }

    private func retryDeferredSpaceTransforms(from masterId: UUID) async {
        let deferred = await gameModel.deferredSpaceTransforms(from: masterId)
        for model in deferred {
            switch await playerSpaceTransformValidation(for: model) {
            case .awaitingAuthoritativeList:
                continue
            case .mismatch:
                await gameModel.removeDeferredSpaceTransform(model)
            case .valid:
                await gameModel.removeDeferredSpaceTransform(model)
                _ = await root.spaceRoot.spaceGameControllable.applySpaceTransform(
                    data: model.data,
                    counter: model.counter,
                    timestamp: model.timestamp
                )
            }
        }
    }

    private func deferredPresentationIsCurrent(_ model: GameNetworkModel) async -> Bool {
        await gameModel.shouldProcessPresentation(
            from: model.masterId,
            senderID: model.sender.id,
            module: model.data.type,
            itemId: model.data.id,
            version: model.data.version,
            counter: model.counter,
            timestamp: model.timestamp,
            isRepair: false
        )
    }

    @MainActor
    private func reportAudioAvailableToCurrentPlayers(itemId: UUID, model: GameNetworkModel) {
        var playerIds = Set(root.audioRoot.gameControllable.gameModel.currentPlayers)
        if playerIds.isEmpty {
            playerIds.formUnion(model.masterState?.controls.compactMap { $0.show ? $0.id : nil } ?? [])
        }
        playerIds.insert(model.masterId)
        for playerId in playerIds {
            root.audioRoot.gameControllable.report(itemId: itemId, for: playerId)
        }
    }

    func handleDice(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        let features = await root.gameModel.gameControl.features
        guard await (root.gameModel.gameConfig.id != model.sender.id) &&
                (features.diceMaster || !model.sender.isMaster) &&
                (features.dicePlayers || model.sender.isMaster)
        else { return await response(for: model, isSuccess: false, requestData: false) }

        // Peers may contribute only a complete roll. Dice focus/visibility and
        // package commands remain master-authoritative even if a player stamps
        // the envelope with a group audience.
        guard model.sender.isMaster || model.isPlayerDiceGroupEvent else {
            return nil
        }
        
        switch model.type {
        case .reveal:
            if try await !root.diceRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) {
                return await response(for: model, isSuccess: true, requestData: true)
            }
            return await response(for: model, isSuccess: true, requestData: false)
        case .store:
            try await root.diceRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: model.subType == .show)
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            switch model.subType {
            case .show, .store:
                try await root.diceRoot.diceGameControllable.updateGame(data: model.data, hide: model.subType == .store, focus: model.subType == .show)
            case .generic:
                _ = await root.diceRoot.diceGameControllable.addGameDiceResult(data: model.data, name: model.senderName, isGameMaster: model.sender.isMaster)
                break
            default:
                break
            }
        }
        return nil
    }
    
    func handleMap(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        guard model.subType != .ok, model.subType != .failed else { return nil }

        let isPlayerMapPin = model.sender.role == .player &&
            model.type == .update &&
            model.subType == .mapPin &&
            model.data.type == .map &&
            model.effectiveAudience == .group
        if isPlayerMapPin {
            switch await applyPlayerMapPin(model) {
            case .applied, .rejected:
                break
            case .awaitingMapGeneration:
                await gameModel.deferMapPin(model)
            }
            return nil
        }

        guard model.sender.isMaster else { return nil }

        switch model.type {
        case .reveal:
            let isRepairPayload = model.targetId != nil || model.subType == .store
            if !isRepairPayload,
               model.data.data != nil,
               let pending = await gameModel.pendingMapRepairRequirement(itemId: model.data.id),
               await !gameModel.pendingMapRepairMatches(model.data),
               model.counter > pending.counter {
                // A newer ordinary show is a fresh authoritative intent, not an
                // answer to the older request. Replace the queued repair so its
                // stale state/content cannot be applied to the new generation.
                await gameModel.supersedeMapRepair(itemId: model.data.id)
            }
            if isRepairPayload {
                guard await gameModel.pendingMapRepairRequirement(itemId: model.data.id) != nil,
                      await gameModel.pendingMapRepairMatches(model.data)
                else { return nil }
            }

            let hasBaseMap = await root.mapRoot.gameControllable.hasItem(
                id: model.data.id,
                version: 0
            )
            let hasMatchingAsset: Bool
            if hasBaseMap, model.data.assetVersion != nil {
                hasMatchingAsset = await hasMatchingMapAsset(model.data)
            } else {
                hasMatchingAsset = false
            }
            let shouldImportFullPayload: Bool
            if model.data.data == nil {
                shouldImportFullPayload = true
            } else {
                shouldImportFullPayload = await gameModel.shouldImportFullMapContent(
                    itemId: model.data.id,
                    counter: model.counter
                )
            }
            var importedFullPayload = false
            let revealed: Bool
            if model.data.data != nil, model.data.assetVersion != nil {
                if hasBaseMap, !shouldImportFullPayload {
                    // A newer full/photo-free update already won. Keep its
                    // metadata while honoring this reveal only when the local
                    // background is the exact advertised asset generation.
                    revealed = hasMatchingAsset
                } else {
                    // Current-protocol full payloads carry independent asset and
                    // content fingerprints. Always import a newly sequenced one:
                    // the background may have changed without the legacy scale
                    // version changing, or its structural snapshot may be newer
                    // even though the background still matches.
                    do {
                        try await root.mapRoot.gameControllable.updateGame(
                            data: model.data,
                            hide: true,
                            deep: false
                        )
                    } catch {
                        return nil
                    }
                    importedFullPayload = true
                    revealed = await hasMatchingMapAsset(model.data)
                }
            } else if model.data.data == nil, model.data.assetVersion != nil {
                // Mutable map metadata may have changed while the background
                // asset stayed the same. Current peers can reuse that asset and
                // wait for the companion mapUpdate; legacy peers still follow
                // the original scale-version comparison in reveal().
                // A reference for a different background asset must request the
                // full Journal/messenger package even when the legacy scale-only
                // `version` still matches the local MapModel.
                revealed = hasMatchingAsset
            } else {
                do {
                    revealed = try await root.mapRoot.gameControllable.reveal(
                        itemId: model.data.id,
                        data: model.data,
                        save: false
                    )
                } catch {
                    return nil
                }
                importedFullPayload = revealed && model.data.data != nil
            }

            guard revealed else {
                await MainActor.run {
                    if gameModel.gameUpdateType == .photo {
                        gameModel.gameUpdateType = .none
                    }
                }
                guard !isRepairPayload else { return nil }
                return await requestFullMap(
                    for: model,
                    requestType: .reveal,
                    action: model.subType,
                    presentsMap: true
                )
            }

            if importedFullPayload {
                await root.mapRoot.mapGameControllable.recordAuthoritativeMapGeneration(
                    model.data
                )
                await gameModel.recordFullMapContentVersion(
                    itemId: model.data.id,
                    contentVersion: model.data.contentVersion,
                    counter: model.counter
                )
            }
            _ = await applyPendingMapContentUpdate(itemId: model.data.id)

            // A metadata-only reveal is complete only when both independent
            // generations are locally available. Missing a structural update is
            // repaired exactly once for that advertised content fingerprint.
            if model.data.data == nil,
               await !gameModel.hasMapContentVersion(
                    itemId: model.data.id,
                    contentVersion: model.data.contentVersion
               ) {
                return await requestMapContent(
                    for: model,
                    presentsMap: true
                )
            }

            guard await root.mapRoot.mapGameControllable.hasBackgroundImage(itemId: model.data.id) else {
                // Never ACK or present an unusable Map. One retry per exact
                // asset/content generation bounds a permanently broken export.
                return await requestFullMap(
                    for: model,
                    requestType: .reveal,
                    action: model.subType == .store ? .mapState : model.subType,
                    presentsMap: true,
                    backgroundRetry: true
                )
            }

            _ = await applyPendingMapState(itemId: model.data.id)
            let hadPendingRepair = await gameModel.pendingMapRepairRequirement(itemId: model.data.id) != nil
            let completedRepair = await completeMapRepairIfSatisfied(itemId: model.data.id)
            guard !hadPendingRepair || completedRepair != nil else { return nil }
            await presentMap(itemId: model.data.id)
            return await response(for: model, isSuccess: true, requestData: false)

        case .store:
            guard model.data.data != nil else { return nil }
            if await gameModel.pendingMapRepairRequirement(itemId: model.data.id) != nil,
               await !gameModel.pendingMapRepairMatches(model.data) {
                return nil
            }

            let hasBaseMap = await root.mapRoot.gameControllable.hasItem(id: model.data.id, version: 0)
            let shouldImport = await gameModel.shouldImportFullMapContent(
                itemId: model.data.id,
                counter: model.counter
            )
            var importedFullPayload = false
            if !hasBaseMap || shouldImport {
                do {
                    try await root.mapRoot.gameControllable.updateGame(
                        data: model.data,
                        hide: true,
                        deep: true
                    )
                } catch {
                    return nil
                }
                importedFullPayload = true
                await root.mapRoot.mapGameControllable.recordAuthoritativeMapGeneration(
                    model.data
                )
                await gameModel.recordFullMapContentVersion(
                    itemId: model.data.id,
                    contentVersion: model.data.contentVersion,
                    counter: model.counter
                )
            } else if await !hasMatchingMapAsset(model.data) {
                return nil
            }

            _ = await applyPendingMapContentUpdate(itemId: model.data.id)
            _ = await applyPendingMapState(itemId: model.data.id)
            await retryDeferredMapPins(itemId: model.data.id)
            guard await root.mapRoot.mapGameControllable.hasBackgroundImage(itemId: model.data.id) else {
                return await requestFullMap(
                    for: model,
                    requestType: .store,
                    action: .store,
                    presentsMap: false,
                    backgroundRetry: true
                )
            }

            let hadPendingRepair = await gameModel.pendingMapRepairRequirement(itemId: model.data.id) != nil
            let completesPresentation = await completeMapRepairIfSatisfied(itemId: model.data.id)
            guard !hadPendingRepair || completesPresentation != nil else { return nil }
            if completesPresentation == true {
                await presentMap(itemId: model.data.id)
            } else if importedFullPayload {
                await requestMissingMapImages(itemId: model.data.id)
            }
            return await response(for: model, isSuccess: true, requestData: false)

        case .update:
            switch model.subType {
            case .generic:
                return await handleMapContentUpdate(model)
            case .mapState:
                guard await gameModel.shouldApplyMapState(
                        itemId: model.data.id,
                        counter: model.counter
                      )
                else { return nil }

                let hasBaseMap = await root.mapRoot.gameControllable.hasItem(
                    id: model.data.id,
                    version: 0
                )
                let hasMatchingAsset = await hasMatchingMapAsset(model.data)
                let hasMatchingContent = await gameModel.hasMapContentVersion(
                    itemId: model.data.id,
                    contentVersion: model.data.contentVersion
                )
                guard hasBaseMap, hasMatchingAsset else {
                    await gameModel.queueMapState(model.data, counter: model.counter)
                    return await requestFullMap(
                        for: model,
                        requestType: .reveal,
                        action: .mapState,
                        presentsMap: true
                    )
                }
                guard hasMatchingContent else {
                    await gameModel.queueMapState(model.data, counter: model.counter)
                    return await requestMapContent(for: model, presentsMap: true)
                }

                guard await root.mapRoot.mapGameControllable.updateMap(
                    for: model.data.id,
                    with: model.data
                ) else { return nil }
                await gameModel.markMapStateApplied(itemId: model.data.id, counter: model.counter)
                _ = await completeMapRepairIfSatisfied(itemId: model.data.id)
                await retryDeferredMapPins(itemId: model.data.id)
                await MainActor.run { gameModel.gameUpdateType = .map }
                await refreshMapVisuals(itemId: model.data.id)

            case .mapPin:
                // Player pin events are handled before the master-only switch.
                return nil
            case .battleRound:
                guard await root.mapRoot.mapGameControllable.applyBattleRoundUpdate(
                    for: model.data.id,
                    with: model.data
                ) else { return nil }
                await MainActor.run { gameModel.gameUpdateType = .map }
            default:
                return nil
            }
        }
        return nil
    }

    func handleMapContentUpdate(_ model: GameNetworkModel) async -> GameNetworkModel? {
        guard model.sender.isMaster,
              model.data.type == .map,
              model.data.data != nil
        else { return nil }
        guard await gameModel.shouldApplyMapContentUpdate(
            itemId: model.data.id,
            counter: model.counter
        ) else { return nil }

        let hasBaseMap = await root.mapRoot.gameControllable.hasItem(id: model.data.id, version: 0)
        let hasMatchingAsset = await hasMatchingMapAsset(model.data)
        guard hasBaseMap, hasMatchingAsset else {
            await gameModel.queueMapContentUpdate(model.data, counter: model.counter)
            return await requestFullMap(
                for: model,
                requestType: .reveal,
                action: .mapState,
                presentsMap: false
            )
        }

        guard await root.mapRoot.mapGameControllable.applyMapContentUpdate(
            for: model.data.id,
            with: model.data
        ) else { return nil }
        await gameModel.markMapContentUpdateApplied(
            itemId: model.data.id,
            counter: model.counter,
            contentVersion: model.data.contentVersion
        )
        _ = await applyPendingMapState(itemId: model.data.id)
        await retryDeferredMapPins(itemId: model.data.id)
        let completesPresentation = await completeMapRepairIfSatisfied(itemId: model.data.id)
        if completesPresentation == true {
            await presentMap(itemId: model.data.id)
        } else if let pending = await gameModel.pendingMapRepairRequirement(itemId: model.data.id),
                  await !root.mapRoot.mapGameControllable.hasBackgroundImage(itemId: model.data.id) {
            return await requestFullMap(
                for: model,
                requestType: .reveal,
                action: .mapState,
                presentsMap: pending.presentsMap,
                backgroundRetry: true
            )
        } else {
            await refreshMapVisuals(itemId: model.data.id)
        }
        return nil
    }

    func applyPendingMapContentUpdate(itemId: UUID) async -> Bool {
        guard let pending = await gameModel.pendingMapContentUpdate(for: itemId) else { return false }
        guard await gameModel.shouldApplyMapContentUpdate(
            itemId: itemId,
            counter: pending.counter
        ) else {
            await gameModel.discardPendingMapContentUpdate(itemId: itemId)
            return false
        }
        guard await root.mapRoot.gameControllable.hasItem(id: itemId, version: 0),
              await hasMatchingMapAsset(pending.data),
              await root.mapRoot.mapGameControllable.applyMapContentUpdate(
                for: itemId,
                with: pending.data
              )
        else { return false }

        await gameModel.markMapContentUpdateApplied(
            itemId: itemId,
            counter: pending.counter,
            contentVersion: pending.data.contentVersion
        )
        return true
    }

    func applyPendingMapState(itemId: UUID) async -> Bool {
        guard let pending = await gameModel.pendingMapState(for: itemId) else { return false }
        guard await gameModel.shouldApplyMapState(itemId: itemId, counter: pending.counter) else {
            await gameModel.discardPendingMapState(itemId: itemId)
            return false
        }
        guard await root.mapRoot.gameControllable.hasItem(id: itemId, version: 0),
              await hasMatchingMapAsset(pending.data),
              await gameModel.hasMapContentVersion(
                itemId: itemId,
                contentVersion: pending.data.contentVersion
              )
        else { return false }

        guard await root.mapRoot.mapGameControllable.updateMap(
            for: itemId,
            with: pending.data
        ) else {
            await gameModel.discardPendingMapState(itemId: itemId)
            return false
        }
        await gameModel.markMapStateApplied(itemId: itemId, counter: pending.counter)
        return true
    }

    func hasMatchingMapAsset(_ data: NetworkCodableDataType) async -> Bool {
        guard let expectedAssetVersion = data.assetVersion else { return true }
        return await root.mapRoot.mapGameControllable.mapAssetVersion(for: data.id) == expectedAssetVersion
    }

    func completeMapRepairIfSatisfied(itemId: UUID) async -> Bool? {
        guard let requirement = await gameModel.pendingMapRepairRequirement(itemId: itemId) else {
            return nil
        }
        if let expectedAssetVersion = requirement.assetVersion,
           await root.mapRoot.mapGameControllable.mapAssetVersion(for: itemId) != expectedAssetVersion {
            return nil
        }
        guard await gameModel.hasMapContentVersion(
            itemId: itemId,
            contentVersion: requirement.contentVersion
        ), await root.mapRoot.mapGameControllable.hasBackgroundImage(itemId: itemId) else {
            return nil
        }
        return await gameModel.completeMapRepair(itemId: itemId)
    }

    func requestFullMap(
        for model: GameNetworkModel,
        requestType: RPGMessageType,
        action: RPGMessageActionType,
        presentsMap: Bool,
        backgroundRetry: Bool = false
    ) async -> GameNetworkModel? {
        let shouldRequest = if backgroundRetry {
            await gameModel.beginMapBackgroundRepair(
                itemId: model.data.id,
                assetVersion: model.data.assetVersion,
                contentVersion: model.data.contentVersion,
                presentsMap: presentsMap,
                counter: model.counter
            )
        } else {
            await gameModel.beginMapRepair(
                itemId: model.data.id,
                assetVersion: model.data.assetVersion,
                contentVersion: model.data.contentVersion,
                presentsMap: presentsMap,
                counter: model.counter
            )
        }
        guard shouldRequest else { return nil }

        return await MainActor.run {
            root.gameModel.outgoingMessage(
                replyToMessageID: model.messageID,
                counter: model.counter,
                proxyCounter: model.proxyCounter,
                type: requestType,
                subType: action,
                asMaster: false,
                purpose: .assetRequest,
                data: NetworkCodableDataType(
                    id: model.data.id,
                    type: .map,
                    version: model.data.version,
                    data: nil,
                    assetVersion: model.data.assetVersion,
                    contentVersion: model.data.contentVersion
                )
            )
        }
    }

    func requestMapContent(
        for model: GameNetworkModel,
        presentsMap: Bool
    ) async -> GameNetworkModel? {
        guard await gameModel.beginMapRepair(
            itemId: model.data.id,
            assetVersion: model.data.assetVersion,
            contentVersion: model.data.contentVersion,
            presentsMap: presentsMap,
            counter: model.counter
        ) else { return nil }

        return await MainActor.run {
            root.gameModel.outgoingMessage(
                replyToMessageID: model.messageID,
                counter: model.counter,
                proxyCounter: model.proxyCounter,
                type: .update,
                subType: .generic,
                asMaster: false,
                purpose: .assetRequest,
                data: NetworkCodableDataType(
                    id: model.data.id,
                    type: .map,
                    version: model.data.version,
                    data: nil,
                    assetVersion: model.data.assetVersion,
                    contentVersion: model.data.contentVersion
                )
            )
        }
    }

    func presentMap(itemId: UUID) async {
        _ = await root.mapRoot.gameControllable.setCurrent(itemId: itemId)
        await retryDeferredMapPins(itemId: itemId)
        await MainActor.run { gameModel.gameUpdateType = .map }
        await refreshMapVisuals(itemId: itemId)
    }

    @MainActor
    private func applyPlayerMapPin(_ model: GameNetworkModel) -> PlayerMapPinApplication {
        guard root.mapRoot.gameControllable.gameModel.currentItemId == model.data.id else {
            return .awaitingMapGeneration
        }
        let generation = root.mapRoot.mapGameControllable.networkMapUpdate(for: model.data.id)
        guard model.data.version == generation.version,
              model.data.assetVersion == generation.assetVersion,
              model.data.contentVersion == generation.contentVersion
        else {
            return .awaitingMapGeneration
        }
        guard root.mapRoot.mapGameControllable.updatePinIfCurrentGeneration(
            itemId: model.data.id,
            data: model.data,
            playerId: model.sender.id
        ) else {
            return .rejected
        }

        _ = root.mapRoot.mapGameControllable.synchronizeBattleDefenders(itemId: model.data.id)
        #if !os(tvOS)
        root.gameModel.gameTableModel?.syncPawnsWithMapPins()
        #endif
        return .applied
    }

    @MainActor
    private func retryDeferredMapPins(itemId: UUID) {
        guard root.mapRoot.gameControllable.gameModel.currentItemId == itemId else { return }
        let generation = root.mapRoot.mapGameControllable.networkMapUpdate(for: itemId)
        let deferred = gameModel.consumeDeferredMapPins(for: itemId, matching: generation)
        var didApplyPin = false
        for model in deferred {
            didApplyPin = root.mapRoot.mapGameControllable.updatePinIfCurrentGeneration(
                itemId: itemId,
                data: model.data,
                playerId: model.sender.id
            ) || didApplyPin
        }
        guard didApplyPin else { return }

        _ = root.mapRoot.mapGameControllable.synchronizeBattleDefenders(itemId: itemId)
        #if !os(tvOS)
        root.gameModel.gameTableModel?.syncPawnsWithMapPins()
        #endif
    }

    func refreshMapVisuals(itemId: UUID) async {
        // mapState carries pin metadata but not newly referenced photo models.
        // The background itself remains exclusive to the full Map package.
        await requestMissingMapImages(itemId: itemId)
        #if !os(tvOS)
        let isGameMaster = await root.gameModel.gameConfig.isMaster
        await root.gameModel.gameTableModel?.updateFogOfWar(isGameMaster: isGameMaster)
        await MainActor.run {
            root.gameModel.gameTableModel?.syncPawnsWithMapPins()
        }
        #endif
    }

    /// Requests pin photos absent from both the photo game state and persistent
    /// item controller. The map background is delivered with the full map.
    /// Each photo is requested once per connection; SharePlay turns the first
    /// full answer into one group store so peers do not transfer it again.
    func requestMissingMapImages(itemId: UUID) async {
        let missingImages = await root.mapRoot.mapGameControllable.missingMapImages(itemId: itemId)
        for idType in missingImages {
            let isFirstRequest = await MainActor.run { gameModel.requestedRepairIds.insert(idType.id).inserted }
            guard isFirstRequest else { continue }
            await send(
                type: .store,
                subType: .store,
                updated: idType,
                relayToProxyClients: false,
                purpose: .assetRequest
            )
        }
    }

    func handlePdf(
        _ model: GameNetworkModel,
        locallyMirroredProxyPresentation: Bool = false
    ) async throws -> GameNetworkModel? {
        guard model.subType != .ok, model.subType != .failed else { return nil }

        let masterId = model.masterId
        if model.sender.isMaster,
           model.type == .reveal,
           model.subType == .show,
           model.targetId == nil {
            await gameModel.removeDeferredPdfReveals(from: masterId)
        }
        if model.sender.isMaster,
           !(model.type == .update && model.subType == .pdfList) {
            let previousBaseline = await root.pdfRoot.pdfGameControllable.masterVersion(
                for: model.data.id,
                masterId: masterId
            )
            if previousBaseline != nil, previousBaseline != model.data.effectiveAssetVersion {
                await MainActor.run { _ = gameModel.requestedPdfRepairIds.remove(model.data.id) }
            }
            await root.pdfRoot.pdfGameControllable.setMasterVersion(
                itemId: model.data.id,
                version: model.data.effectiveAssetVersion,
                masterId: masterId
            )
        }

        let validPlayerReveal: Bool
        if locallyMirroredProxyPresentation, model.isPlayerFilePresentationEvent {
            validPlayerReveal = true
        } else if model.sender.isMaster || !model.isPlayerFilePresentationEvent {
            validPlayerReveal = false
        } else {
            switch await playerPdfRevealValidation(for: model) {
            case .valid:
                validPlayerReveal = true
            case .awaitingAuthoritativeList:
                await gameModel.deferPdfReveal(model)
                return nil
            case .mismatch:
                return nil
            }
        }

        guard model.sender.isMaster || model.type == .store || validPlayerReveal else { return nil }

        switch model.type {
        case .reveal:
            if try await root.pdfRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) {
                await MainActor.run {
                    _ = gameModel.requestedPdfRepairIds.remove(model.data.id)
                    gameModel.gameUpdateType = .pdf
                }
                let localPlayerId = await root.gameModel.gameConfig.id
                await root.pdfRoot.pdfGameControllable.markPdfAvailable(
                    itemId: model.data.id,
                    version: model.data.effectiveAssetVersion,
                    for: [localPlayerId, model.sender.id],
                    masterId: masterId
                )
                if model.data.data != nil, model.targetId == nil {
                    await root.pdfRoot.pdfGameControllable.markPdfAvailableToCurrentPlayers(
                        itemId: model.data.id,
                        version: model.data.effectiveAssetVersion,
                        masterId: masterId
                    )
                }
                return await response(for: model, isSuccess: true, requestData: false)
            }

            let isFirstRequest = await MainActor.run {
                gameModel.requestedPdfRepairIds.insert(model.data.id).inserted
            }
            guard isFirstRequest else { return nil }
            let baseline = await root.pdfRoot.pdfGameControllable.masterVersion(
                for: model.data.id,
                masterId: masterId
            )
            var requestTrigger = model
            requestTrigger.type = .store
            requestTrigger.subType = .store
            return await response(
                for: requestTrigger,
                isSuccess: true,
                requestData: true,
                requestedVersion: baseline
            )
        case .store:
            try await root.pdfRoot.gameControllable.updateGame(
                data: model.data,
                hide: model.subType == .store,
                deep: true
            )
            let hasLocalData = await root.pdfRoot.gameControllable.hasLocalFileData(for: model.data.id)
            if hasLocalData {
                let completesReveal = await MainActor.run {
                    gameModel.requestedPdfRepairIds.remove(model.data.id) != nil
                }
                if completesReveal, await root.pdfRoot.gameControllable.setCurrent(itemId: model.data.id) {
                    await MainActor.run { gameModel.gameUpdateType = .pdf }
                }
                let localPlayerId = await root.gameModel.gameConfig.id
                await root.pdfRoot.pdfGameControllable.markPdfAvailable(
                    itemId: model.data.id,
                    version: model.data.effectiveAssetVersion,
                    for: [localPlayerId],
                    masterId: masterId
                )
                return await response(for: model, isSuccess: true, requestData: false)
            }
            return nil
        case .update:
            guard model.subType == .pdfList else { return nil }
            guard await applyPdfList(model) else { return nil }
            await retryDeferredPdfReveals(from: model.masterId)
            return nil
        }
    }

    func handlePhoto(
        _ model: GameNetworkModel,
        locallyMirroredProxyPresentation: Bool = false
    ) async throws -> GameNetworkModel? {
        guard model.subType != .ok, model.subType != .failed else { return nil }

        let masterId = model.masterId
        if model.sender.isMaster,
           model.type == .reveal,
           model.subType == .show,
           model.targetId == nil {
            // A canonical master presentation supersedes any peer reveal that
            // was waiting for availability evidence from this master.
            await gameModel.removeDeferredPhotoReveals(from: masterId)
        }
        if model.sender.isMaster,
           !(model.type == .update && model.subType == .photoList) {
            await root.photoRoot.photoGameControllable.setMasterVersion(
                itemId: model.data.id,
                version: model.data.effectiveAssetVersion,
                masterId: masterId
            )
        }

        let validPlayerReveal: Bool
        if locallyMirroredProxyPresentation, model.isPlayerFilePresentationEvent {
            validPlayerReveal = true
        } else if model.sender.isMaster || !model.isPlayerFilePresentationEvent {
            validPlayerReveal = false
        } else {
            switch await playerPhotoRevealValidation(for: model) {
            case .valid:
                validPlayerReveal = true
            case .awaitingAuthoritativeList:
                await gameModel.deferPhotoReveal(model)
                return nil
            case .mismatch:
                return nil
            }
        }

        guard model.sender.isMaster || model.type == .store || validPlayerReveal else { return nil }

        switch model.type {
        case .reveal:
            if try await root.photoRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) {
                await MainActor.run {
                    gameModel.gameUpdateType = .photo
                }

                let localPlayerId = await root.gameModel.gameConfig.id
                await root.photoRoot.photoGameControllable.markPhotoAvailable(
                    itemId: model.data.id,
                    version: model.data.effectiveAssetVersion,
                    for: [localPlayerId, model.sender.id],
                    masterId: masterId
                )
                if model.data.data != nil, model.targetId == nil {
                    await root.photoRoot.photoGameControllable.markPhotoAvailableToCurrentPlayers(
                        itemId: model.data.id,
                        version: model.data.effectiveAssetVersion,
                        masterId: masterId
                    )
                }
                return await response(for: model, isSuccess: true, requestData: false)
            } else {
                let baseline = await root.photoRoot.photoGameControllable.masterVersion(
                    for: model.data.id,
                    masterId: masterId
                )
                return await response(
                    for: model,
                    isSuccess: true,
                    requestData: true,
                    requestedVersion: baseline
                )
            }
        case .store:
            try await root.photoRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
            let hasLocalData = await root.photoRoot.gameControllable.hasLocalFileData(for: model.data.id)
            if hasLocalData {
                await MainActor.run { _ = gameModel.requestedRepairIds.remove(model.data.id) }
                let localPlayerId = await root.gameModel.gameConfig.id
                await root.photoRoot.photoGameControllable.markPhotoAvailable(
                    itemId: model.data.id,
                    version: model.data.effectiveAssetVersion,
                    for: [localPlayerId],
                    masterId: masterId
                )
            }
            return await response(for: model, isSuccess: hasLocalData, requestData: !hasLocalData)
        case .update:
            switch model.subType {
            case .photoList:
                guard await applyPhotoList(model) else { return nil }
                await retryDeferredPhotoReveals(from: model.masterId)
                return nil
            default:
                if model.data.data != nil {
                    try await root.photoRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
                }
            }
            if await root.photoRoot.gameControllable.setCurrent(itemId: model.data.id) {
                await MainActor.run {
                    gameModel.gameUpdateType = .photo
                }
            }
        }
        return nil
    }
    
    func handleTable(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        guard model.subType != .ok, model.subType != .failed else { return nil }

        switch model.type {
        case .reveal:
            // The co-located game-master player receives its own Table reveal
            // as a reference. Its persistent Table is the canonical source, so
            // an exact-version reference can be selected directly without the
            // session-availability cache used by remote players. Otherwise the
            // local echo asks for bytes, but that upstream request is correctly
            // suppressed to avoid a master/local-player loop and the master UI
            // never changes.
            if await gameModel.asGameMaster,
               model.sender.isMaster,
               model.data.data == nil,
               model.data.version != 0,
               await root.tableRoot.gameControllable.networkVersion(for: model.data.id) == model.data.version,
               await root.tableRoot.gameControllable.setCurrent(itemId: model.data.id) {
                await MainActor.run {
                    gameModel.gameUpdateType = .table
                }
                return await response(for: model, isSuccess: true, requestData: false)
            }
            if try await root.tableRoot.tableGameControllable.receiveTable(
                itemId: model.data.id,
                data: model.data,
                makeCurrent: true
            ) {
                await MainActor.run {
                    gameModel.gameUpdateType = .table
                }
                return await response(for: model, isSuccess: true, requestData: false)
            } else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
        case .store:
            if try await root.tableRoot.tableGameControllable.receiveTable(
                itemId: model.data.id,
                data: model.data,
                makeCurrent: false
            ) {
                return await response(for: model, isSuccess: true, requestData: false)
            }
            return await response(for: model, isSuccess: true, requestData: true)
        case .update:
            return nil
        }
    }
    
    func handleValue(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        guard await root.gameModel.gameType != .proxy else { return try await handleProxyValue(model) }
        // A normal player accepts only the master's targeted response to the
        // join announcement. No Value reveal, result, loot, or live update is
        // processed during the game.
        guard model.sender.isMaster,
              model.type == .update,
              model.subType == .store,
              model.data.data == nil,
              let characterId = await root.gameModel.gamePlayer.characterId,
              characterId == model.data.id
        else { return nil }

        try Task.checkCancellation()
        let package = try await root.characterRoot.gameControllable.createGameData(for: characterId)
        try Task.checkCancellation()
        // Character packages can be large, but only the game master consumes
        // them. Keep them off the SharePlay Journal and away from local proxy
        // clients; SharePlay peers may see the Messenger message and ignore it.
        await send(
            type: .update,
            subType: .store,
            updated: package,
            useJournal: false,
            relayToProxyClients: false
        )
        return nil
    }
    
    func handleWeather(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        guard model.subType != .ok, model.subType != .failed else { return nil }

        switch model.type {
        case .reveal:
            if try await root.weatherRoot.weatherGameControllable.revealWeather(
                itemId: model.data.id,
                data: model.data
            ) {
                await MainActor.run {
                    gameModel.gameUpdateType = .weather
                }
                return await response(for: model, isSuccess: true, requestData: false)
            } else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
        case .store:
            // Weather packages are game-session assets. Even legacy store
            // messages must stay in game memory and never enter persistence.
            try await root.weatherRoot.gameControllable.updateGame(data: model.data, hide: true, deep: true)
            await root.weatherRoot.weatherGameControllable.markWeatherAvailable(
                itemId: model.data.id,
                version: model.data.version
            )
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            // Weather is immutable during a game. Presentation and repair use
            // reveal messages; live update messages are intentionally ignored.
            break
        }
        return nil
    }
    
    func handleSpace(
        _ model: GameNetworkModel,
        locallyMirroredProxyPresentation: Bool = false
    ) async throws -> GameNetworkModel? {
        guard model.subType != .ok, model.subType != .failed else { return nil }

        let masterId = model.masterId
        if model.sender.isMaster,
           model.type == .reveal,
           model.subType == .show,
           model.targetId == nil {
            await gameModel.removeDeferredSpaceReveals(from: masterId)
        }
        if model.sender.isMaster,
           !(model.type == .update && (model.subType == .spaceList || model.subType == .spaceTransform)) {
            let previousBaseline = await root.spaceRoot.spaceGameControllable.masterVersion(
                for: model.data.id,
                masterId: masterId
            )
            if previousBaseline != nil, previousBaseline != model.data.effectiveAssetVersion {
                await MainActor.run { _ = gameModel.requestedSpaceRepairIds.remove(model.data.id) }
            }
            await root.spaceRoot.spaceGameControllable.setMasterVersion(
                itemId: model.data.id,
                version: model.data.effectiveAssetVersion,
                masterId: masterId
            )
        }

        let validPlayerReveal: Bool
        if locallyMirroredProxyPresentation, model.isPlayerFilePresentationEvent {
            validPlayerReveal = true
        } else if model.sender.isMaster || !model.isPlayerFilePresentationEvent {
            validPlayerReveal = false
        } else {
            switch await playerSpaceRevealValidation(for: model) {
            case .valid:
                validPlayerReveal = true
            case .awaitingAuthoritativeList:
                await gameModel.deferSpaceReveal(model)
                return nil
            case .mismatch:
                return nil
            }
        }

        let isPlayerSpaceTransform = model.sender.role == .player &&
            model.type == .update &&
            model.subType == .spaceTransform &&
            model.data.type == .space &&
            model.effectiveAudience == .group

        guard model.sender.isMaster || model.type == .store || validPlayerReveal || isPlayerSpaceTransform else {
            return nil
        }

        switch model.type {
        case .reveal:
            if try await root.spaceRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) {
                await MainActor.run {
                    _ = gameModel.requestedSpaceRepairIds.remove(model.data.id)
                    gameModel.gameUpdateType = .space

                    #if os(visionOS)
                    if root.networkStore.sharePlayStore.isActive {
                        // Switch the presentation mode; the modeChanged observer
                        // reconfigures the spatial template, and the game screen
                        // opens the immersive space when it shows the space module.
                        root.gameModel.shareState.mode = .immersive
                    }
                    #endif
                }
                let localPlayerId = await root.gameModel.gameConfig.id
                await root.spaceRoot.spaceGameControllable.markSpaceAvailable(
                    itemId: model.data.id,
                    version: model.data.effectiveAssetVersion,
                    for: [localPlayerId, model.sender.id],
                    masterId: masterId
                )
                if model.data.data != nil, model.targetId == nil {
                    await root.spaceRoot.spaceGameControllable.markSpaceAvailableToCurrentPlayers(
                        itemId: model.data.id,
                        version: model.data.effectiveAssetVersion,
                        masterId: masterId
                    )
                }
                return await response(for: model, isSuccess: true, requestData: false)
            } else {
                let isFirstRequest = await MainActor.run {
                    gameModel.requestedSpaceRepairIds.insert(model.data.id).inserted
                }
                guard isFirstRequest else { return nil }
                let baseline = await root.spaceRoot.spaceGameControllable.masterVersion(
                    for: model.data.id,
                    masterId: masterId
                )
                return await response(
                    for: model,
                    isSuccess: true,
                    requestData: true,
                    requestedVersion: baseline
                )
            }
        case .store:
            try await root.spaceRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
            let hasLocalData = await root.spaceRoot.gameControllable.hasLocalFileData(for: model.data.id)
            if hasLocalData {
                let completesReveal = await MainActor.run {
                    gameModel.requestedSpaceRepairIds.remove(model.data.id) != nil
                }
                if completesReveal,
                   await root.spaceRoot.gameControllable.setCurrent(itemId: model.data.id) {
                    await MainActor.run {
                        gameModel.gameUpdateType = .space

                        #if os(visionOS)
                        if root.networkStore.sharePlayStore.isActive {
                            root.gameModel.shareState.mode = .immersive
                        }
                        #endif
                    }
                }
                let localPlayerId = await root.gameModel.gameConfig.id
                await root.spaceRoot.spaceGameControllable.markSpaceAvailable(
                    itemId: model.data.id,
                    version: model.data.effectiveAssetVersion,
                    for: [localPlayerId],
                    masterId: masterId
                )
                return await response(for: model, isSuccess: true, requestData: false)
            }
            let isFirstRequest = await MainActor.run {
                gameModel.requestedSpaceRepairIds.insert(model.data.id).inserted
            }
            guard isFirstRequest else { return nil }
            return await response(for: model, isSuccess: true, requestData: true)
        case .update:
            switch model.subType {
            case .spaceList:
                guard await applySpaceList(model) else { return nil }
                await retryDeferredSpaceReveals(from: model.masterId)
                await retryDeferredSpaceTransforms(from: model.masterId)
                return nil
            case .spaceTransform:
                let baseline = await root.spaceRoot.spaceGameControllable.masterVersion(
                    for: model.data.id,
                    masterId: model.masterId
                )
                guard baseline == nil || baseline == model.data.effectiveAssetVersion else { return nil }
                if !model.sender.isMaster {
                    switch await playerSpaceTransformValidation(for: model) {
                    case .valid:
                        break
                    case .awaitingAuthoritativeList:
                        await gameModel.deferSpaceTransform(model)
                        return nil
                    case .mismatch:
                        return nil
                    }
                }
                _ = await root.spaceRoot.spaceGameControllable.applySpaceTransform(
                    data: model.data,
                    counter: model.counter,
                    timestamp: model.timestamp
                )
                return nil
            default:
                break
            }
            if await root.spaceRoot.gameControllable.setCurrent(itemId: model.data.id) {
                await MainActor.run {
                    gameModel.gameUpdateType = .space
                }
            }
        }
        return nil
    }
    
    func handleProxyValue(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        // The one proxy-specific Value flow is the host Character bootstrap.
        // Ignore every other legacy Value action or metadata-only message.
        guard model.sender.isMaster,
              model.type == .update,
              model.subType == .store,
              model.data.data != nil
        else { return nil }

        try await root.characterRoot.gameControllable.updateGame(data: model.data, hide: false, deep: true)
        await scheduleProxyFocus(characterId: model.data.id)
        return nil
    }
    
    nonisolated func response(
        for model: GameNetworkModel,
        isSuccess: Bool,
        requestData: Bool,
        requestedVersion: Int? = nil
    ) async -> GameNetworkModel {
        let subType: RPGMessageActionType = requestData ? model.subType : (isSuccess ? .ok : .failed)
        // A "please send more" request only needs to name the item: the master
        // rebuilds the payload from `data.id` via createGameData and never reads
        // these bytes. Echoing `model.data` verbatim used to re-upload whatever
        // we just received — e.g. a map that's merely short its background photo
        // sent its whole multi-MB self straight back upstream over the slow,
        // small-message-oriented player→master path, for nothing.
        let preservesAssetVersion = model.data.type == .photo ||
            model.data.type == .pdf ||
            model.data.type == .space ||
            model.data.type == .map ||
            model.data.type == .table ||
            model.data.type == .weather
        let version = if requestData {
            requestedVersion ?? model.data.version
        } else if preservesAssetVersion {
            model.data.version
        } else {
            0
        }
        let payload = NetworkCodableDataType(
            id: model.data.id,
            type: model.data.type,
            version: version,
            data: nil,
            assetVersion: preservesAssetVersion && requestedVersion == nil ? model.data.assetVersion : nil,
            contentVersion: preservesAssetVersion ? model.data.contentVersion : nil
        )
        // Echo the counter of the message being answered (same precedent as the
        // mapState re-request below) instead of minting a fresh one. The pipeline
        // already deduplicates the incoming trigger, so this stays exactly-once;
        // it also lets the master's message log match the ack back to the row it
        // created for the original send — with a fresh counter here that link
        // was counter-space garbage and the log's delivery indicator could never
        // leave "missing players", on every transport, not just file sharing.
        return await MainActor.run {
            root.gameModel.outgoingMessage(
                replyToMessageID: model.messageID,
                counter: model.counter,
                proxyCounter: model.proxyCounter,
                type: model.type,
                subType: subType,
                asMaster: false,
                purpose: requestData ? .assetRequest : .event,
                data: payload
            )
        }
    }

    func scheduleSendCharacter() async {
        await MainActor.run {
            guard gameModel.sendCharacterTask == nil else { return }
            let taskId = UUID()
            gameModel.sendCharacterTaskId = taskId
            gameModel.sendCharacterTask = Task { [weak self] in
                await self?.sendCharacter()
                await MainActor.run {
                    guard self?.gameModel.sendCharacterTaskId == taskId else { return }
                    self?.gameModel.sendCharacterTask = nil
                    self?.gameModel.sendCharacterTaskId = nil
                }
            }
        }
    }

    func scheduleProxyFocus(characterId: UUID) async {
        await MainActor.run {
            gameModel.proxyFocusTask?.cancel()
            let taskId = UUID()
            gameModel.proxyFocusTaskId = taskId
            gameModel.proxyFocusTask = Task { [weak self] in
                guard let self else { return }
                _ = await root.characterRoot.gameControllable.setCurrent(itemId: characterId)
                await root.characterRoot.gameControllable.focus(on: characterId)
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    await MainActor.run {
                        guard self.gameModel.proxyFocusTaskId == taskId else { return }
                        self.gameModel.proxyFocusTask = nil
                        self.gameModel.proxyFocusTaskId = nil
                    }
                    return
                }
                guard !Task.isCancelled else {
                    await MainActor.run {
                        guard self.gameModel.proxyFocusTaskId == taskId else { return }
                        self.gameModel.proxyFocusTask = nil
                        self.gameModel.proxyFocusTaskId = nil
                    }
                    return
                }
                await MainActor.run {
                    guard gameModel.proxyFocusTaskId == taskId else { return }
                    root.gameModel.selectedCharacter = characterId
                    gameModel.proxyFocusTask = nil
                    gameModel.proxyFocusTaskId = nil
                }
            }
        }
    }
    
    func sendCharacter() async {
        let gameType = await root.gameModel.gameType
        let canSend = await MainActor.run { !gameModel.hasSendPlayer && !gameModel.lostMaster }
        // A proxy device never announces a character: it mirrors the host
        // player and receives the host's character on readyProxy instead.
        guard canSend, gameType != .observer, gameType != .proxy,
              let characterId = await root.gameModel.gamePlayer.characterId
        else { return }

        do {
            try Task.checkCancellation()
            let reference = await root.characterRoot.gameControllable.share(id: characterId)
            try Task.checkCancellation()
            // First advertise only the Character ID and deterministic version.
            // The master requests the full package only when its local version
            // differs. Value messages never use the SharePlay Journal.
            await send(
                type: .update,
                subType: .store,
                updated: reference,
                useJournal: false,
                relayToProxyClients: false
            )
            let lostMaster = await gameModel.lostMaster
            guard !Task.isCancelled, !lostMaster else { return }
            await gameModel.reset(sendPlayer: true)
        } catch is CancellationError {
            return
        } catch {
            Logger.networking.error("PlayerController: Failed to send character \(characterId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func sendAudioList() async {
        // A proxy device stays invisible: the host answers for its audio
        // availability, and the host consumes any list that still arrives.
        guard await root.gameModel.gameType != .proxy else { return }
        let audioList = await root.audioRoot.audioGameControllable.audioList(allPlayers: false, with: root.gameModel.gameConfig.id)
        await send(type: .update, subType: .audioList, updated: audioList, useJournal: false)
    }

    func sendPhotoList() async {
        // A proxy is a private mirror of its host and must not become a separate
        // availability-report participant.
        guard await root.gameModel.gameType != .proxy else { return }
        let photoList = await root.photoRoot.photoGameControllable.photoList(
            allPlayers: false,
            with: root.gameModel.gameConfig.master.id
        )
        await send(type: .update, subType: .photoList, updated: photoList, useJournal: false)
    }

    func sendPdfList() async {
        // A proxy mirrors its host and must not become an availability-report
        // participant of its own.
        guard await root.gameModel.gameType != .proxy else { return }
        let pdfList = await root.pdfRoot.pdfGameControllable.pdfList(
            allPlayers: false,
            with: root.gameModel.gameConfig.master.id
        )
        await send(type: .update, subType: .pdfList, updated: pdfList, useJournal: false)
    }

    func sendSpaceList() async {
        // A proxy mirrors its host and must not appear as a separate participant
        // in the Space availability/version matrix.
        guard await root.gameModel.gameType != .proxy else { return }
        let spaceList = await root.spaceRoot.spaceGameControllable.spaceList(
            allPlayers: false,
            with: root.gameModel.gameConfig.master.id
        )
        await send(type: .update, subType: .spaceList, updated: spaceList, useJournal: false)
    }
}
