// @copyright André Trettin

import Foundation

/// Compares a module's iCloud folder with its items and applies what the user chose: adds items
/// for files without one, moves items to where their file is, and trashes items whose file is
/// gone. Stateless: the sheet's model holds the state.
struct CloudScanController: Sendable {
    let itemController: any ItemControllable
    let editController: any EditControllable

    enum ScanResult: Equatable {
        case plan(CloudScanPlan)
        /// The module folder cannot be read, while items reference files in it. Every item would
        /// look like its file is gone.
        case unreachable
    }

    enum Outcome: Equatable {
        case synced(added: Int, folders: Int, moved: Int, trashed: Int)
        /// An import, a repair or another bulk write is running.
        case busy
        /// The folder could not be listed again, so nothing was applied. Nothing is trashed, moved
        /// or added from a picture that may be out of date. See CODE_AUDIT_22a §5.1.
        case unreachable
    }

    /// Whether the module keeps its files in iCloud at all.
    @MainActor var isAvailable: Bool {
        itemController.fileUrlDataController != nil
    }

    /// What differs between the iCloud folder and the items. Nothing is changed.
    /// `nil` when the module has no files or the scan was cancelled.
    @MainActor func scan() async -> ScanResult? {
        guard let files = itemController.fileUrlDataController else { return nil }
        let moduleUrl = files.cloudDocumentController.moduleUrl
        let existing = itemController.cloudScanExistingItems()
        let listing = await CloudFolderScan.listing(below: moduleUrl, fileTypes: itemController.config.fileTypes)
        guard !Task.isCancelled else { return nil }
        guard let listing else {
            return existing.contains { $0.fileComponents != nil } ? .unreachable : .plan(CloudScanPlan())
        }
        let listed = listing.files
        let hashes = await CloudFolderScan.hashes(of: CloudFolderScan.hashCandidates(files: listed, existing: existing), below: moduleUrl)
        guard !Task.isCancelled else { return nil }
        return .plan(CloudFolderScan.plan(
            files: listed,
            existing: existing,
            module: itemController.config.module.token,
            hashes: hashes,
            unreadableFolders: listing.unreadableFolders
        ))
    }

    /// Applies `plan` and saves. The folder is listed again first: the plan is shown to the user
    /// and sync keeps running, so a file that came back or moved on is not trashed or moved from
    /// the old picture, and a file that went is not added; when the folder cannot be listed again
    /// nothing is applied (`.unreachable`). What the library has meanwhile is not added or changed
    /// a second time.
    @MainActor func apply(_ plan: CloudScanPlan) async -> Outcome {
        let current = await scan()
        let hashes = await newItemHashes(of: plan)
        guard let token = DataMutationCoordinator.shared.begin() else { return .busy }
        defer { DataMutationCoordinator.shared.end(token) }

        // Without a fresh plan nothing is applied: it cannot be told whether the old picture still
        // holds, and the user is told so instead of seeing a sync of zero.
        guard case let .plan(currentPlan)? = current else { return .unreachable }
        var confirmed = plan
        let currentRemovals = Set(currentPlan.removals.map(\.id))
        let currentItems = Set(currentPlan.items.map(\.id))
        let currentFolders = Set(currentPlan.folders.map(\.id))
        let currentMoves = Dictionary(currentPlan.moves.map { ($0.id, $0.to) }, uniquingKeysWith: { first, _ in first })
        confirmed.removals.removeAll { !currentRemovals.contains($0.id) }
        confirmed.items.removeAll { !currentItems.contains($0.id) }
        confirmed.folders.removeAll { !currentFolders.contains($0.id) }
        confirmed.moves.removeAll { currentMoves[$0.id] != $0.to }

        let known = Set(itemController.itemDataModel.items)
        var fresh = confirmed
        fresh.folders.removeAll { known.contains($0.id) }
        fresh.items.removeAll { known.contains($0.id) }

        var changedIds = itemController.insertCloudScan(fresh, hashes: hashes)
        let movedIds = itemController.moveCloudScanItems(confirmed.moves)
        changedIds += movedIds
        editController.repairFolders(itemIds: Set(changedIds))

        let module = itemController.config.module
        let trashed = confirmed.removals.filter { removal in
            guard let item = itemController.itemSync(for: removal.id, noGame: true) else { return false }
            return item.displayState != DisplayStateMask.totalHidden.rawValue
        }
        editController.confirmRemoval(of: trashed.map { ItemRowModel(itemId: $0.id, typeId: module) }, keeping: [])

        await itemController.save()
        return .synced(added: fresh.items.count, folders: fresh.folders.count, moved: movedIds.count, trashed: trashed.count)
    }

    /// The content hashes of the files that become items, read off the main actor.
    @MainActor private func newItemHashes(of plan: CloudScanPlan) async -> [String: String] {
        guard !plan.items.isEmpty, let files = itemController.fileUrlDataController else { return [:] }
        return await CloudFolderScan.hashes(of: plan.items.map(\.file), below: files.cloudDocumentController.moduleUrl)
    }
}
