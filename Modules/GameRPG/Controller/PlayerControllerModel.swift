// @copyright André Trettin

import CoreRPG
import Foundation
import MapRPG

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

    /// Reads both gate flags in one @MainActor property so a concurrent
    /// writer can't be observed between them. See CODE_AUDIT §3.1.
    var canSendCharacter: Bool { !hasSendPlayer && !lostMaster }

    /// The read-then-conditionally-write needs to stay one @MainActor call so a
    /// concurrent reader never observes a state between the check and the clear.
    /// See CODE_AUDIT §3.1.
    func clearGameUpdateTypeIfPhoto() {
        if gameUpdateType == .photo {
            gameUpdateType = .none
        }
    }

    /// Clears the pdf repair-pending flag and marks the pdf update atomically,
    /// so a concurrent reader never observes one change without the other.
    /// See CODE_AUDIT §3.1.
    func completePdfRepairAndSetUpdateType(_ id: UUID) {
        requestedPdfRepairIds.remove(id)
        gameUpdateType = .pdf
    }

    // Named per-set mutators for every `pending*Requests`/`requested*RepairIds`
    // single-id `Set<UUID>` in this model — a keypath-generic pair (tried first)
    // doesn't compile: Swift disallows forming a key path to an actor-isolated
    // stored property at all, from anywhere, since the resulting `KeyPath` value
    // itself carries no isolation. See CODE_AUDIT §3.1.
    @discardableResult
    func removePendingAudioRequest(_ id: UUID) -> Bool {
        pendingAudioRequests.remove(id) != nil
    }

    @discardableResult
    func insertPendingAudioRequest(_ id: UUID) -> Bool {
        pendingAudioRequests.insert(id).inserted
    }

    @discardableResult
    func removeRequestedRepairId(_ id: UUID) -> Bool {
        requestedRepairIds.remove(id) != nil
    }

    @discardableResult
    func insertRequestedRepairId(_ id: UUID) -> Bool {
        requestedRepairIds.insert(id).inserted
    }

    @discardableResult
    func removeRequestedPdfRepairId(_ id: UUID) -> Bool {
        requestedPdfRepairIds.remove(id) != nil
    }

    @discardableResult
    func insertRequestedPdfRepairId(_ id: UUID) -> Bool {
        requestedPdfRepairIds.insert(id).inserted
    }

    @discardableResult
    func removeRequestedSpaceRepairId(_ id: UUID) -> Bool {
        requestedSpaceRepairIds.remove(id) != nil
    }

    @discardableResult
    func insertRequestedSpaceRepairId(_ id: UUID) -> Bool {
        requestedSpaceRepairIds.insert(id).inserted
    }

    /// The batch of per-connection state a lost connection must clear atomically,
    /// pulled out of `PlayerController.resetForLostConnection` so the multi-property
    /// reset stays one `@MainActor` call from the controller instead of a
    /// `MainActor.run` closure. See CODE_AUDIT §3.1.
    func resetForLostConnection(preservingSharePlayRebind: Bool) {
        sendCharacterTask?.cancel()
        sendCharacterTask = nil
        sendCharacterTaskId = nil
        pendingMapRequests = []
        pendingAudioRequests = []
        requestedRepairIds = []
        requestedPdfRepairIds = []
        requestedSpaceRepairIds = []
        resetMasterStateSequence()
        resetAudioListSequence()
        resetPhotoListSequence()
        resetPdfListSequence()
        resetSpaceListSequence()
        resetPresentationSequence()
        resetMapContentSequence()
        if !preservingSharePlayRebind {
            resetSharePlayMasterParticipant()
        }
    }
}
