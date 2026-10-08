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
final class PlayerControllerModel {
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

    // Deferred-buffer caps — hoisted to match MasterControllerModel's
    // equivalents (`maximumDeliveryMessages` et al.). See CODE_AUDIT_Game §9.20.
    private static let maximumDeferredPhotoReveals = 32
    private static let maximumDeferredPdfReveals = 32
    private static let maximumDeferredSpaceReveals = 32
    private static let maximumDeferredSpaceTransforms = 64
    private static let maximumDeferredMapPins = 64

    private struct PresentationIntent: Sendable {
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

    private struct MapRepairFailures: Equatable, Sendable {
        let assetVersion: Int?
        let contentVersion: Int?
        var count: Int
    }

    /// A map repair to request again after the master answered `.failed`.
    struct MapRepairRetry: Equatable, Sendable {
        let itemId: UUID
        let assetVersion: Int?
        let contentVersion: Int?
        let attempt: Int
    }

    /// How often one map generation's repair is re-requested after a `.failed` answer.
    static let maximumMapRepairRetries = 3

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
    // `GroupSessionMessenger` can redeliver the master's own complete
    // broadcast well after the fact — e.g. one sent just before the master
    // dropped, arriving after `removeSharePlayMasterParticipant` already
    // unbound the slot. Without remembering departed participant IDs, that
    // stale broadcast rebinds the slot to the now-departed identity, and the
    // master's genuine reconnect (a new participant ID) is then permanently
    // rejected — nothing ever clears a denylist entry for the old ID again.
    // Bounded to a small capacity: only ever a few master churns occur in one
    // session. See CODE_AUDIT_Reconnect §3.2.
    private var departedSharePlayMasterParticipantIds = PhysicalIdentityDenylist<UUID>(capacity: 16)
    var lostMaster: Bool = true
    var hasSendPlayer = false
    /// How often the master answered `.failed` to this player's Character package, for which
    /// Character version, and when the next announcement may go out. A rejected package was
    /// announced again on every later master message, and exported and uploaded again each
    /// time, with no limit. See CODE_AUDIT_21 §5.5.
    private(set) var characterRejections = 0
    private var rejectedCharacterVersion: Int?
    private var characterRetryNotBefore: ContinuousClock.Instant?
    /// Rejections of one Character version after which it is no longer sent.
    static let maximumCharacterRejections = 3
    /// How often a rejected Character is looked at again for a changed version.
    static let rejectedCharacterProbeInterval: Duration = .seconds(60)
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
    /// `.failed` answers per map for the generation of its pending repair.
    /// See CODE_AUDIT_19 §5.6.
    private var mapRepairFailures: [UUID: MapRepairFailures] = [:]
    @ObservationIgnored private var mapRepairRetryTasks: [UUID: Task<Void, Never>] = [:]
    /// Latest `.battleRound` update that arrived while its map generation was
    /// not yet current on this device — mirrors `pendingMapStates`, not the
    /// per-pin `deferredMapPins`: there is only one battle-round state per
    /// map, and `BattleRoundNetworkState.sequence` (checked inside
    /// `applyRemoteState`) already rejects a stale replay, so only the single
    /// latest deferred payload per map needs to be retained. See CODE_AUDIT §5.2.
    private var pendingBattleRoundUpdates: [UUID: NetworkCodableDataType] = [:]

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
            // A stale, redelivered broadcast from an already-departed
            // participant must never re-bind the slot out from under a
            // genuine reconnect under a new participant ID. See
            // `departedSharePlayMasterParticipantIds`'s own doc.
            guard !departedSharePlayMasterParticipantIds.contains(id) else { return .rejected }
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
        departedSharePlayMasterParticipantIds.insert(id)
        return true
    }

    func resetSharePlayMasterParticipant() {
        sharePlayMasterParticipantId = nil
        resynchronizeAfterSharePlayMasterRebind = false
        departedSharePlayMasterParticipantIds.removeAll()
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

        while deferredPhotoRevealOrder.count > Self.maximumDeferredPhotoReveals {
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

        while deferredPdfRevealOrder.count > Self.maximumDeferredPdfReveals {
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

        while deferredSpaceRevealOrder.count > Self.maximumDeferredSpaceReveals {
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

        while deferredSpaceTransformOrder.count > Self.maximumDeferredSpaceTransforms {
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
              let pin = MapPinModel.decodeData(of: data),
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

        while deferredMapPinOrder.count > Self.maximumDeferredMapPins {
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

    /// See CODE_AUDIT §5.2 — replay slot for a `.battleRound` update whose
    /// generation didn't match at receipt time. Always overwrites: a later
    /// deferral is always at least as recent as an earlier one, and
    /// `applyRemoteState`'s own sequence check is the final arbiter of
    /// whether a replay is still worth applying.
    func queueBattleRoundUpdate(_ data: NetworkCodableDataType) {
        pendingBattleRoundUpdates[data.id] = data
    }

    func pendingBattleRoundUpdate(for itemId: UUID) -> NetworkCodableDataType? {
        pendingBattleRoundUpdates[itemId]
    }

    func discardPendingBattleRoundUpdate(itemId: UUID) {
        pendingBattleRoundUpdates[itemId] = nil
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
        clearMapRepairFailures(itemId: itemId)
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
        clearMapRepairFailures(itemId: itemId)
        return presentsMap
    }

    /// The master answered the pending repair with `.failed` (too many deferred repairs, or
    /// an export failure). `beginMapRepair` coalesces an identical pending repair, so without
    /// a retry the map stayed broken until the GM changed its generation.
    ///
    /// Returns the retry to schedule, or `nil` when no repair is pending or this generation
    /// has failed `maximumMapRepairRetries` times; then the pending repair is dropped, so the
    /// next announcement of the map may request it again. See CODE_AUDIT_19 §5.6.
    func failMapRepair(itemId: UUID) -> MapRepairRetry? {
        guard let repair = pendingMapRepairs[itemId] else { return nil }
        var failures = mapRepairFailures[itemId]
        if failures?.assetVersion != repair.assetVersion || failures?.contentVersion != repair.contentVersion {
            failures = MapRepairFailures(assetVersion: repair.assetVersion, contentVersion: repair.contentVersion, count: 0)
        }
        failures?.count += 1
        mapRepairFailures[itemId] = failures
        let attempt = failures?.count ?? 1
        guard attempt <= Self.maximumMapRepairRetries else {
            pendingMapRepairs[itemId] = nil
            pendingMapBackgroundRepairs[itemId] = nil
            pendingMapRequests.remove(itemId)
            return nil
        }
        return MapRepairRetry(
            itemId: itemId,
            assetVersion: repair.assetVersion,
            contentVersion: repair.contentVersion,
            attempt: attempt
        )
    }

    /// Whether `retry`'s generation is still the pending repair for its map.
    func isMapRepairPending(_ retry: MapRepairRetry) -> Bool {
        guard let repair = pendingMapRepairs[retry.itemId] else { return false }
        return repair.assetVersion == retry.assetVersion && repair.contentVersion == retry.contentVersion
    }

    func setMapRepairRetryTask(_ task: Task<Void, Never>, itemId: UUID) {
        mapRepairRetryTasks[itemId]?.cancel()
        mapRepairRetryTasks[itemId] = task
    }

    private func clearMapRepairFailures(itemId: UUID) {
        mapRepairFailures[itemId] = nil
        mapRepairRetryTasks.removeValue(forKey: itemId)?.cancel()
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
        mapRepairFailures.removeAll()
        mapRepairRetryTasks.values.forEach { $0.cancel() }
        mapRepairRetryTasks.removeAll()
        deferredMapPins.removeAll()
        deferredMapPinOrder.removeAll()
        pendingBattleRoundUpdates.removeAll()
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
    var canSendCharacter: Bool {
        guard !hasSendPlayer, !lostMaster else { return false }
        if let characterRetryNotBefore, ContinuousClock.now < characterRetryNotBefore { return false }
        return true
    }

    /// The delay before the announcement after the `rejections`-th rejection: 5 s, then 20 s.
    static func characterRetryDelay(afterRejection rejections: Int) -> Duration {
        .seconds(5 * (1 << (2 * max(0, rejections - 1))))
    }

    /// Records the master's `.failed` answer for the Character package of `version`. Returns
    /// `true` when that was the rejection after which the Character is no longer sent, so the
    /// caller tells the player once. See CODE_AUDIT_21 §5.5.
    func recordCharacterRejection(version: Int, now: ContinuousClock.Instant = .now) -> Bool {
        if rejectedCharacterVersion != version {
            rejectedCharacterVersion = version
            characterRejections = 0
        }
        characterRejections += 1
        hasSendPlayer = false
        guard characterRejections < Self.maximumCharacterRejections else {
            characterRetryNotBefore = now + Self.rejectedCharacterProbeInterval
            return characterRejections == Self.maximumCharacterRejections
        }
        characterRetryNotBefore = now + Self.characterRetryDelay(afterRejection: characterRejections)
        return false
    }

    /// Whether the Character of `version` may be announced. A version the master rejected
    /// `maximumCharacterRejections` times stays unsent; it is looked at again after the probe
    /// interval, because an edited Character has a new version and gets new attempts.
    func mayAnnounceCharacter(version: Int, now: ContinuousClock.Instant = .now) -> Bool {
        guard characterRejections >= Self.maximumCharacterRejections else { return true }
        guard rejectedCharacterVersion == version else {
            resetCharacterRejections()
            return true
        }
        characterRetryNotBefore = now + Self.rejectedCharacterProbeInterval
        return false
    }

    /// A new connection, or an edited Character: earlier rejections no longer count.
    func resetCharacterRejections() {
        characterRejections = 0
        rejectedCharacterVersion = nil
        characterRetryNotBefore = nil
    }

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
        resetCharacterRejections()
        sendCharacterTask?.cancel()
        sendCharacterTask = nil
        sendCharacterTaskId = nil
        // See CODE_AUDIT_Game §3.10 — this task's delayed completion must not
        // overwrite `selectedCharacter` after the session it belongs to is gone.
        proxyFocusTask?.cancel()
        proxyFocusTask = nil
        proxyFocusTaskId = nil
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
