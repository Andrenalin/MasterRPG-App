// @copyright André Trettin

import CoreRPG
import Foundation

@MainActor @Observable
final class SpaceGameModel {
    // See CODE_AUDIT_Game §9.12 — shared with GameRPG/MapRPG's identical policy.
    private static let maximumFutureTransformTimestampSkew = NetworkTimestampPolicy.maximumFutureSkew
    init() {}

    var openSpace: Bool = false

    /// Latest master-sequenced placement for each Space and asset version. A
    /// delayed transform for an older file must not replace the retained pose
    /// of the version that is currently being presented.
    var transformStates: [UUID: [Int: SpaceTransformState]] = [:]

    @discardableResult
    func applyTransform(
        itemId: UUID,
        version: Int,
        counter: Int,
        timestamp: TimeInterval = 0,
        transform: SpaceTransformModel
    ) -> Bool {
        guard counter >= 0,
              timestamp.isFinite,
              timestamp >= 0,
              timestamp <= Date.now.timeIntervalSince1970 + Self.maximumFutureTransformTimestampSkew
        else { return false }
        if let current = transformStates[itemId]?[version] {
            if timestamp > 0 {
                if current.timestamp > 0 {
                    // Current envelopes are ordered only by their shared wall
                    // clock. Counters belong to independent senders and cannot
                    // safely break an equal-timestamp tie.
                    guard timestamp > current.timestamp else { return false }
                }
            } else {
                guard current.timestamp == 0 else { return false }
                if counter == 0 {
                    guard current.counter == 0 else { return false }
                } else {
                    guard counter > current.counter else { return false }
                }
            }
        }
        transformStates[itemId, default: [:]][version] = SpaceTransformState(
            version: version,
            counter: counter,
            timestamp: timestamp,
            transform: transform
        )
        return true
    }

    func transform(for itemId: UUID, version: Int) -> SpaceTransformModel? {
        transformState(for: itemId, version: version)?.transform
    }

    func transformState(for itemId: UUID, version: Int) -> SpaceTransformState? {
        guard let versions = transformStates[itemId] else { return nil }
        if version == 0 {
            return versions.values.max {
                if $0.timestamp == $1.timestamp {
                    return $0.counter < $1.counter
                }
                return $0.timestamp < $1.timestamp
            }
        }
        return versions[version] ?? versions[0]
    }

    /// Returns a current-format timestamp that is causally after the retained
    /// transform while remaining inside the same admission bound as incoming
    /// events. `nil` means the retained clock is already at or beyond the safe
    /// future boundary and a local event must wait for wall time to catch up.
    func causalTransformTimestamp(
        for itemId: UUID,
        version: Int,
        now: TimeInterval = Date.now.timeIntervalSince1970
    ) -> TimeInterval? {
        guard now.isFinite, now > 0 else { return nil }
        let upperBound = now + Self.maximumFutureTransformTimestampSkew
        guard upperBound.isFinite else { return nil }

        guard let current = transformState(for: itemId, version: version),
              current.timestamp > 0
        else { return now }

        let timestamp = max(now, current.timestamp.nextUp)
        guard timestamp <= upperBound else { return nil }
        return timestamp
    }

    func removeTransforms(for itemId: UUID, exceptVersion version: Int) {
        guard var versions = transformStates[itemId] else { return }
        versions = versions.filter { $0.key == 0 || $0.key == version }
        transformStates[itemId] = versions.isEmpty ? nil : versions
    }

    func resetTransforms() {
        transformStates.removeAll()
    }

    func reset() {
        openSpace = false
        resetTransforms()
    }
}

struct SpaceTransformState: Equatable, Sendable {
    let version: Int
    let counter: Int
    let timestamp: TimeInterval
    let transform: SpaceTransformModel
}

public struct SpaceTransformReplayModel: Sendable {
    public let data: NetworkCodableDataType
    public let timestamp: TimeInterval

    public init(data: NetworkCodableDataType, timestamp: TimeInterval) {
        self.data = data
        self.timestamp = timestamp
    }
}

public protocol SpaceGameControllable: Sendable {
    @MainActor func spaceList(allPlayers: Bool, with masterId: UUID) async -> NetworkCodableDataType
    @discardableResult
    @MainActor func applySpaceList(
        data: NetworkCodableDataType,
        for playerId: UUID,
        with masterId: UUID,
        authoritative: Bool
    ) async -> Bool
    @MainActor func masterVersion(for itemId: UUID, masterId: UUID) -> Int?
    @MainActor func reportedVersion(for itemId: UUID, playerId: UUID) -> Int?
    @MainActor func setMasterVersion(itemId: UUID, version: Int, masterId: UUID)
    @MainActor func isSpaceAvailable(itemId: UUID, for playerId: UUID, masterId: UUID) -> Bool
    @MainActor func markSpaceAvailable(itemId: UUID, version: Int, for playerIds: [UUID], masterId: UUID)
    @MainActor func removeSpaceReports(for playerId: UUID)

    @MainActor func isValidSpaceTransform(_ data: NetworkCodableDataType) -> Bool
    @MainActor func applySpaceTransform(
        data: NetworkCodableDataType,
        counter: Int,
        timestamp: TimeInterval
    ) -> Bool
    @MainActor func causalSpaceTransformTimestamp(itemId: UUID, version: Int) -> TimeInterval?
    @MainActor func latestSpaceTransform(for itemId: UUID, version: Int) -> NetworkCodableDataType?
    @MainActor func latestSpaceTransformReplay(
        for itemId: UUID,
        version: Int
    ) -> SpaceTransformReplayModel?
    @MainActor func resetSpaceTransforms()
}

/// Default implementations forwarding to `FileVersionGameControllable` —
/// SpaceRPG previously hand-duplicated all of this (the version-tracking
/// half of `SpaceGameModel`, and every method below except the
/// transform-specific ones) verbatim from PdfRPG/PhotoRPG's own
/// identically-shaped copies, differing only in type/method names. See
/// CODE_AUDIT_10 §9.2.
@MainActor
public extension SpaceGameControllable where Self: FileVersionGameControllable, ListRequest == SpaceListRequest {
    func spaceList(allPlayers: Bool, with masterId: UUID) async -> NetworkCodableDataType {
        await fileList(allPlayers: allPlayers, with: masterId)
    }

    @discardableResult
    func applySpaceList(
        data: NetworkCodableDataType,
        for playerId: UUID,
        with masterId: UUID,
        authoritative: Bool
    ) async -> Bool {
        await applyFileList(data: data, for: playerId, with: masterId, authoritative: authoritative)
    }

    func isSpaceAvailable(itemId: UUID, for playerId: UUID, masterId: UUID) -> Bool {
        isFileAvailable(itemId: itemId, for: playerId, masterId: masterId)
    }

    func markSpaceAvailable(itemId: UUID, version: Int, for playerIds: [UUID], masterId: UUID) {
        markFileAvailable(itemId: itemId, version: version, for: playerIds, masterId: masterId)
    }

    func removeSpaceReports(for playerId: UUID) {
        removeFileReports(for: playerId)
    }
}

struct GameController: Sendable {
    @MainActor init(itemController: ItemController, exportController: ExportController) {
        self.itemController = itemController
        self.exportController = exportController

        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
        self.spaceGameModel = SpaceGameModel()
        self.versionLedger = PlayerVersionLedger()
    }

    let itemController: ItemController
    let exportController: ExportController

    let gameModel: ItemGameModel
    let spaceGameModel: SpaceGameModel
    let versionLedger: PlayerVersionLedger
}

// gameItem(for:)/setGame(item:itemId:)/currentItem() come from
// ModuleGameControllable's default implementations. See CODE_AUDIT_Game §9.1.
extension GameController: ModuleGameControllable {}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }

    @MainActor func resetGameState() {
        versionLedger.reset()
        spaceGameModel.reset()
    }
}

extension GameController: FileVersionGameControllable {
    typealias ListRequest = SpaceListRequest
    static var fileModuleType: NetworkModules { .space }
}

extension GameController: SpaceGameControllable {
    // `setMasterVersion` additionally prunes stale transforms — not shared
    // with PdfRPG/PhotoRPG, so this is the one method this module keeps its
    // own override of rather than picking up `FileVersionGameControllable`'s
    // default.
    @MainActor
    func setMasterVersion(itemId: UUID, version: Int, masterId: UUID) {
        spaceGameModel.removeTransforms(for: itemId, exceptVersion: version)
        versionLedger.playerVersions[itemId, default: [:]][masterId] = version
        rebuildFileReports(masterVersions: [itemId: version], masterId: masterId, only: itemId)
    }

    @MainActor
    func isValidSpaceTransform(_ data: NetworkCodableDataType) -> Bool {
        guard data.type == .space, let transform = SpaceTransformModel.decodeData(of: data.data) else { return false }
        return transform.isPlausible
    }

    @MainActor
    @discardableResult
    func applySpaceTransform(
        data: NetworkCodableDataType,
        counter: Int,
        timestamp: TimeInterval
    ) -> Bool {
        guard data.type == .space,
              let transform = SpaceTransformModel.decodeData(of: data.data),
              transform.isPlausible
        else { return false }
        return spaceGameModel.applyTransform(
            itemId: data.id,
            version: data.effectiveAssetVersion,
            counter: counter,
            timestamp: timestamp,
            transform: transform
        )
    }

    @MainActor
    func causalSpaceTransformTimestamp(itemId: UUID, version: Int) -> TimeInterval? {
        spaceGameModel.causalTransformTimestamp(for: itemId, version: version)
    }

    @MainActor
    func latestSpaceTransform(for itemId: UUID, version: Int) -> NetworkCodableDataType? {
        latestSpaceTransformReplay(for: itemId, version: version)?.data
    }

    @MainActor
    func latestSpaceTransformReplay(
        for itemId: UUID,
        version: Int
    ) -> SpaceTransformReplayModel? {
        guard let state = spaceGameModel.transformState(for: itemId, version: version),
              let data = state.transform.encodeData()
        else { return nil }

        // A version-zero state is the legacy fallback for a requested asset
        // baseline. Replays must carry that requested baseline so the receiver
        // can apply the retained pose to the asset it requested. A zero request
        // remains a wildcard and preserves the selected state's real version.
        let replayVersion = version == 0 ? state.version : version
        return SpaceTransformReplayModel(
            data: NetworkCodableDataType(
                id: itemId,
                type: .space,
                version: replayVersion,
                data: data
            ),
            timestamp: state.timestamp
        )
    }

    @MainActor
    func resetSpaceTransforms() {
        spaceGameModel.resetTransforms()
    }

    /// Not shared with PdfRPG/PhotoRPG: also prunes every transform pose
    /// that isn't the newly-agreed baseline once that baseline is
    /// determined, matching this module's own `setMasterVersion` override
    /// above.
    @MainActor
    func rebuildFileReports(masterVersions: [UUID: Int], masterId: UUID, only itemId: UUID? = nil) {
        let itemIds: Set<UUID>
        if let itemId {
            itemIds = [itemId]
        } else {
            itemIds = Set(masterVersions.keys)
                .union(versionLedger.playerVersions.keys)
                .union(gameModel.playerReports.keys)
        }

        for itemId in itemIds {
            guard let baseline = masterVersions[itemId] ?? versionLedger.version(for: itemId, playerId: masterId) else {
                gameModel.playerReports[itemId] = []
                continue
            }
            spaceGameModel.removeTransforms(for: itemId, exceptVersion: baseline)
            gameModel.playerReports[itemId] = (versionLedger.playerVersions[itemId] ?? [:])
                .compactMap { playerId, version in version == baseline ? playerId : nil }
                .sorted()
        }
    }
}

public struct SpaceListRequest: FileListRequest {
    public let list: [UUID: Int]
    public let players: [UUID: [UUID: Int]]

    public init(list: [UUID: Int], players: [UUID: [UUID: Int]]) {
        self.list = list
        self.players = players
    }
}
