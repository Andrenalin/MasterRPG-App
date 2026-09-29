// @copyright André Trettin

import Foundation
import Observation

/// Reported file versions keyed by item and participant — the game master's
/// own entry is the canonical baseline every availability decision compares
/// against.
///
/// PdfRPG's, PhotoRPG's, and SpaceRPG's `GameController`s each previously
/// hand-duplicated this exact tracking (the `playerVersions` half of their
/// own `PdfGameModel`/`PhotoGameModel`/`SpaceGameModel`) verbatim. A
/// module with additional game-side state (e.g. SpaceRPG's transform-pose
/// tracking) holds one of these alongside that state rather than
/// reimplementing it. See CODE_AUDIT_10 §9.2.
@MainActor @Observable
public final class PlayerVersionLedger {
    public init() {}

    public var playerVersions: [UUID: [UUID: Int]] = [:]

    public func replace(with versions: [UUID: [UUID: Int]]) {
        playerVersions = versions
    }

    public func apply(_ versions: [UUID: Int], for playerId: UUID) {
        // Snapshot the keys before mutating the dictionary. Removing the last
        // participant can delete an item entry entirely.
        for itemId in Set(playerVersions.keys) {
            playerVersions[itemId]?[playerId] = nil
            if playerVersions[itemId]?.isEmpty == true {
                playerVersions[itemId] = nil
            }
        }
        for (itemId, version) in versions {
            playerVersions[itemId, default: [:]][playerId] = version
        }
    }

    public func remove(playerId: UUID) {
        apply([:], for: playerId)
    }

    public func version(for itemId: UUID, playerId: UUID) -> Int? {
        playerVersions[itemId]?[playerId]
    }

    public func reset() {
        playerVersions.removeAll()
    }
}

/// A network-serializable "here's what I have" list request — one per
/// file-backed module (`PdfListRequest`/`PhotoListRequest`/`SpaceListRequest`),
/// each an identical `{ list, players }` shape under a different name. See
/// CODE_AUDIT_10 §9.2.
public protocol FileListRequest: Codable, Sendable, Equatable, MessageMapper {
    var list: [UUID: Int] { get }
    var players: [UUID: [UUID: Int]] { get }
    init(list: [UUID: Int], players: [UUID: [UUID: Int]])
}

/// Shared by every file-backed module's `GameController` (PdfRPG, PhotoRPG,
/// SpaceRPG) — version-ledger tracking, list request/response, and
/// availability queries that were previously hand-duplicated per module,
/// differing only in type/method names. A conformer supplies `versionLedger`,
/// `fileModuleType`, and its own `ListRequest` type; every method below is a
/// default implementation. Module-specific behavior beyond file-version
/// tracking (e.g. SpaceRPG's transform-pose replay) stays in that module's
/// own `GameController`, unaffected by this protocol. See CODE_AUDIT_10 §9.2.
@MainActor
public protocol FileVersionGameControllable: GameControllable {
    associatedtype ListRequest: FileListRequest
    var versionLedger: PlayerVersionLedger { get }
    static var fileModuleType: NetworkModules { get }

    /// A declared protocol requirement (not just an extension default) so a
    /// conformer with extra per-item state to keep in sync — SpaceRPG prunes
    /// stale transform poses once an item's baseline changes — can override
    /// it and have `setMasterVersion`/`markFileAvailable`/`fileList`/
    /// `applyFileList` below (which all call this) dispatch to that override
    /// dynamically. A plain extension-only method would instead always
    /// resolve to this protocol's own default from within those call sites,
    /// silently ignoring a conformer's override.
    func rebuildFileReports(masterVersions: [UUID: Int], masterId: UUID, only itemId: UUID?)
}

public extension FileVersionGameControllable {
    func masterVersion(for itemId: UUID, masterId: UUID) -> Int? {
        versionLedger.version(for: itemId, playerId: masterId)
    }

    func reportedVersion(for itemId: UUID, playerId: UUID) -> Int? {
        versionLedger.version(for: itemId, playerId: playerId)
    }

    func setMasterVersion(itemId: UUID, version: Int, masterId: UUID) {
        versionLedger.playerVersions[itemId, default: [:]][masterId] = version
        rebuildFileReports(masterVersions: [itemId: version], masterId: masterId, only: itemId)
    }

    func isFileAvailable(itemId: UUID, for playerId: UUID, masterId: UUID) -> Bool {
        guard let baseline = masterVersion(for: itemId, masterId: masterId) else { return false }
        return versionLedger.version(for: itemId, playerId: playerId) == baseline
    }

    func markFileAvailable(itemId: UUID, version: Int, for playerIds: [UUID], masterId: UUID) {
        guard masterVersion(for: itemId, masterId: masterId) == version else { return }
        for playerId in playerIds {
            versionLedger.playerVersions[itemId, default: [:]][playerId] = version
        }
        rebuildFileReports(masterVersions: [itemId: version], masterId: masterId, only: itemId)
    }

    func markFileAvailableToCurrentPlayers(itemId: UUID, version: Int, masterId: UUID) {
        let players = Set(gameModel.currentPlayers).union([masterId])
        markFileAvailable(itemId: itemId, version: version, for: Array(players), masterId: masterId)
    }

    func removeFileReports(for playerId: UUID) {
        versionLedger.remove(playerId: playerId)
        gameModel.removePlayerReport(for: playerId)
    }

    func fileList(allPlayers: Bool, with masterId: UUID) async -> NetworkCodableDataType {
        let localVersions = await localFileVersions()
        let request: ListRequest
        if allPlayers {
            versionLedger.apply(localVersions, for: masterId)
            rebuildFileReports(masterVersions: localVersions, masterId: masterId)
            request = ListRequest(list: localVersions, players: versionLedger.playerVersions)
        } else {
            request = ListRequest(list: localVersions, players: [:])
        }
        return NetworkCodableDataType(id: UUID(), type: Self.fileModuleType, version: 0, data: request.encodeData())
    }

    @discardableResult
    func applyFileList(
        data: NetworkCodableDataType,
        for playerId: UUID,
        with masterId: UUID,
        authoritative: Bool
    ) async -> Bool {
        guard let request = ListRequest.decodeData(of: data.data) else { return false }

        if authoritative {
            var versions = request.players
            for (itemId, version) in request.list {
                versions[itemId, default: [:]][masterId] = version
            }
            versionLedger.replace(with: versions)
            rebuildFileReports(masterVersions: request.list, masterId: masterId)
        } else {
            let masterVersions = await localFileVersions()
            versionLedger.apply(masterVersions, for: masterId)
            versionLedger.apply(request.list, for: playerId)
            rebuildFileReports(masterVersions: masterVersions, masterId: masterId)
        }
        return true
    }

    func localFileVersions() async -> [UUID: Int] {
        var versions: [UUID: Int] = [:]
        for itemId in itemControllable.itemDataModel.items {
            guard await hasLocalDatabaseFileData(for: itemId) else { continue }
            versions[itemId] = await networkVersion(for: itemId)
        }
        return versions
    }

    func hasLocalDatabaseFileData(for itemId: UUID) async -> Bool {
        guard let item = itemControllable.itemSync(for: itemId, noGame: true) else { return false }
        guard let fileUrl = item.fileUrl else { return true }
        guard let fileUrlDataController = itemControllable.fileUrlDataController else { return false }
        // Reported to the master as available: an iCloud file that has not downloaded must not
        // count, or the master sends only a reference to bytes this device cannot read.
        return await fileUrlDataController.hasDownloadedData(for: fileUrl)
    }

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
            gameModel.playerReports[itemId] = (versionLedger.playerVersions[itemId] ?? [:])
                .compactMap { playerId, version in version == baseline ? playerId : nil }
                .sorted()
        }
    }
}
