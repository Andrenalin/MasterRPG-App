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
        let listed = await CloudFolderScan.files(below: moduleUrl, fileTypes: itemController.config.fileTypes)
        guard !Task.isCancelled else { return nil }
        guard let listed else {
            return existing.contains { $0.fileComponents != nil } ? .unreachable : .plan(CloudScanPlan())
        }
        let hashes = await CloudFolderScan.hashes(of: CloudFolderScan.hashCandidates(files: listed, existing: existing), below: moduleUrl)
        guard !Task.isCancelled else { return nil }
        return .plan(CloudFolderScan.plan(files: listed, existing: existing, module: itemController.config.module.token, hashes: hashes))
    }

    /// Applies `plan` and saves. What the library has meanwhile (the plan is shown to the user
    /// first, and sync keeps running) is not added or changed a second time.
    @MainActor func apply(_ plan: CloudScanPlan) async -> Outcome {
        guard let token = DataMutationCoordinator.shared.begin() else { return .busy }
        defer { DataMutationCoordinator.shared.end(token) }

        let known = Set(itemController.itemDataModel.items)
        var fresh = plan
        fresh.folders.removeAll { known.contains($0.id) }
        fresh.items.removeAll { known.contains($0.id) }

        var changedIds = itemController.insertCloudScan(fresh)
        let movedIds = itemController.moveCloudScanItems(plan.moves)
        changedIds += movedIds
        editController.repairFolders(itemIds: Set(changedIds))

        let module = itemController.config.module
        let trashed = plan.removals.filter { removal in
            guard let item = itemController.itemSync(for: removal.id, noGame: true) else { return false }
            return item.displayState != DisplayStateMask.totalHidden.rawValue
        }
        editController.confirmRemoval(of: trashed.map { ItemRowModel(itemId: $0.id, typeId: module) }, keeping: [])

        await itemController.save()
        return .synced(added: fresh.items.count, folders: fresh.folders.count, moved: movedIds.count, trashed: trashed.count)
    }
}
