// @copyright André Trettin

import Foundation

// MARK: - Folder admission

extension PeerImportPolicy {
    /// A folder of a peer package, reduced to what the admission needs.
    struct Folder {
        let id: UUID
        let childIds: [UUID]
        let existsLocally: Bool
    }

    /// Decides the folders of a package after its other items were admitted. A peer's folders
    /// describe the peer's own library: they are only the path of the items the peer brings
    /// along. So a folder is admitted when it passes `admit` and, after its entries are reduced
    /// to the items this peer introduced, still holds one (an admitted inner folder counts). An
    /// entry for an item this device already owns is dropped: it would file that item a second
    /// time in a folder that does not exist here. A folder left without any entry is not
    /// created at all. Returns the entries to keep of each admitted folder.
    func admitFolders(_ folders: [Folder]) -> [UUID: Set<UUID>] {
        var admittedFolders: [UUID: Set<UUID>] = [:]
        var decided: Set<UUID> = []
        var changed = true
        // An inner folder admitted in one round lets its parent folder pass in the next.
        while changed {
            changed = false
            for folder in folders where !decided.contains(folder.id) {
                let introduced = introducedItemIds
                let keptChildIds = Set(folder.childIds.filter { introduced.contains($0) && $0 != folder.id })
                guard !keptChildIds.isEmpty else { continue }
                decided.insert(folder.id)
                guard admit(itemId: folder.id, existsLocally: folder.existsLocally) else { continue }
                admittedFolders[folder.id] = keptChildIds
                changed = true
            }
        }
        // What is left has nothing of this peer in it.
        rejectedItemCount += folders.filter { !decided.contains($0.id) }.count
        return admittedFolders
    }
}
