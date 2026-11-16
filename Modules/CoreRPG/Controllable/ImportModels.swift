// @copyright André Trettin

import Foundation
import Observation

// MARK: - Import State

public enum ImportMode: Hashable, Sendable, CaseIterable {
    case merge, overwrite, manual
}

/// A file an import wrote for an item, and the file that item had before.
/// See CODE_AUDIT_Folder §5.26.
struct ImportedFileWrite: Sendable {
    let written: FileUrl
    let previous: FileUrl?
}

/// Where the items of one module stream go, decided once when the stream starts.
/// See CODE_AUDIT_Folder §3.4.
struct ImportApplyPolicy: Sendable {
    let mode: ImportMode
    let forceSave: Bool
    /// A saved-game load: items go to game memory only, whatever the mode.
    let gameMemoryOnly: Bool
    /// A game delivery that started during a running game: items go to game memory only.
    let writesGameMemory: Bool
    let isUntrustedSource: Bool

    /// The post-import folder repair runs for everything but manual review and saved-game loads.
    var repairsImportedItems: Bool {
        mode != .manual && !gameMemoryOnly
    }
}

/// What a game peer's package may write into this device's library. A peer is only trusted
/// with its own data, so an item is admitted when it is the peer's primary item, was
/// introduced by this same peer before, or does not exist here yet — a package can never
/// overwrite another item the device already owns. The item count is capped as well.
/// See CODE_AUDIT_15 §5.2.
///
/// Known gaps, accepted by design and never to be fixed (CODE_AUDIT_Folder §6.2): ids are not
/// keyed by module and the cap is per package rather than per session. (A new folder's entries
/// pointing at items this device already owns are stripped everywhere, in the library as well
/// as in game memory: see `admitFolders`.) Each gap needs a deliberately crafted
/// package, and only players the game master knows can connect: SharePlay runs among FaceTime
/// friends, a local-network game is played by people at the same table, and a public
/// local-network game needs its join code.
@MainActor
public final class PeerImportPolicy {
    public static let defaultMaximumItems = 256

    public let primaryItemId: UUID
    public let maximumItems: Int
    public private(set) var ownedItemIds: Set<UUID>
    public private(set) var admittedItemIds: Set<UUID> = []
    public internal(set) var rejectedItemCount = 0

    public init(primaryItemId: UUID, ownedItemIds: Set<UUID> = [], maximumItems: Int = PeerImportPolicy.defaultMaximumItems) {
        self.primaryItemId = primaryItemId
        self.ownedItemIds = ownedItemIds
        self.maximumItems = maximumItems
    }

    /// Ids the peer has introduced so far, to hand back to the caller for the next package.
    public var introducedItemIds: Set<UUID> { ownedItemIds.union(admittedItemIds) }

    /// INTENDED BEHAVIOR — do not "fix" (CODE_AUDIT_17 §6.1, decided won't fix): the peer's
    /// primary item (its own Character) is admitted even when it already exists locally, so a
    /// player can overwrite that Character on the master to update its values. Reaching this
    /// path needs a connected peer: LAN is PIN-protected, unknown connections are only accepted
    /// if the game master allows them, and SharePlay is a real FaceTime call.
    func admit(itemId: UUID, existsLocally: Bool) -> Bool {
        let isAllowed = itemId == primaryItemId
            || ownedItemIds.contains(itemId)
            || !existsLocally
        guard isAllowed, admittedItemIds.count < maximumItems || admittedItemIds.contains(itemId) else {
            rejectedItemCount += 1
            return false
        }
        admittedItemIds.insert(itemId)
        return true
    }
}

@MainActor @Observable
public final class ItemDataImportModel {
    public init() {}

    /// Lets a caller set the initial mode atomically with construction — calling an
    /// isolated initializer with `await` works the same as calling an isolated method;
    /// only a bare property *write* on an already-existing instance needs its own
    /// isolated function (see CODE_AUDIT §3.2).
    public convenience init(importMode: ImportMode) {
        self.init()
        self.importMode = importMode
    }

    /// Set for data received from a game peer instead of a file the user picked: the sender
    /// controls every field of it, so imported `FileUrl`s get the strictest sanitising.
    /// See CODE_AUDIT_15 §5.1 / §6.3.
    public convenience init(importMode: ImportMode, isUntrustedSource: Bool) {
        self.init(importMode: importMode)
        self.isUntrustedSource = isUntrustedSource
    }

    public private(set) var isUntrustedSource: Bool = false

    /// Limits what a peer's package may write; see `PeerImportPolicy`.
    public private(set) var peerPolicy: PeerImportPolicy?

    public convenience init(importMode: ImportMode, peerPolicy: PeerImportPolicy?) {
        self.init(importMode: importMode, isUntrustedSource: true)
        self.peerPolicy = peerPolicy
    }

    /// Set for a game delivery that will be stored in the library: its files must reach disk,
    /// the in-memory fallback of a game-only delivery is not enough. See CODE_AUDIT_21 §5.14.
    public private(set) var requiresDurableFiles = false

    public convenience init(importMode: ImportMode, peerPolicy: PeerImportPolicy?, requiresDurableFiles: Bool) {
        self.init(importMode: importMode, peerPolicy: peerPolicy)
        self.requiresDurableFiles = requiresDurableFiles
    }

    public var importedItems: Int = 0
    /// Items of the import that could not be decoded or applied. Shown after the import so a
    /// partly failed file no longer reads as a clean success. See CODE_AUDIT_15 §5.7.
    public var failedItems: Int = 0
    public var totalImportingItems: Int = 0
    public var isImportRunning: Bool = false
    public var importMode: ImportMode = .merge
    public var isReviewReady: Bool = false
    var reviewModel: ImportReviewModel? = nil

    var pendingModules: [NetworkModules: [ImportReviewItemModel]] = [:]

    /// The ids each module's import actually wrote (merged, overwritten or loaded into game
    /// memory); items an unchanged merge skipped are not included. Lets a game delivery see
    /// what a package changed without comparing object identities. See CODE_AUDIT_Folder §5.10,
    /// §5.22.
    public private(set) var appliedItemIds: [NetworkModules: Set<UUID>] = [:]

    /// Files a manual-review import wrote while parsing; cleaned up once the review is applied
    /// or cancelled. See CODE_AUDIT_Folder §5.2.
    var reviewFileWrites: [(module: NetworkModules, itemId: UUID, write: ImportedFileWrite)] = []

    func recordApplied(_ itemId: UUID, module: NetworkModules) {
        appliedItemIds[module, default: []].insert(itemId)
    }
    var isFinalizingImport: Bool {
        isImportRunning
            && totalImportingItems > 0
            && importedItems >= totalImportingItems
    }

    func finalizeReview() {
        let modules = pendingModules
            .map { ImportReviewModule(id: $0.key, reviewItems: $0.value) }
            .sorted { $0.name < $1.name }
        reviewModel = modules.isEmpty ? nil : ImportReviewModel(modules: modules)
        isReviewReady = true
    }
}
