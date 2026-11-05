// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

/// The game master's list of Characters at the table: adds, enables, disables and removes them.
/// The list itself lives in `GameRootModel.tablePlayers`; every change goes through `update`.
@MainActor @Observable
final class TablePlayersModel {
    init(
        tablePlayers: @escaping @MainActor () -> [TablePlayerModel],
        update: @escaping @MainActor ([TablePlayerModel]) -> Void
    ) {
        self.tablePlayers = tablePlayers
        self.update = update
    }

    @ObservationIgnored private let tablePlayers: @MainActor () -> [TablePlayerModel]
    @ObservationIgnored private let update: @MainActor ([TablePlayerModel]) -> Void

    /// The Characters picked while `isPicking`.
    let selectionModel = ItemSelectionModel(isSingleSelection: false, allowCollections: false)
    private(set) var isPicking = false

    func startPicking() {
        selectionModel.resetSelection(selectionIds: [])
        isPicking = true
    }

    func cancelPicking() {
        isPicking = false
        selectionModel.resetSelection(selectionIds: [])
    }

    /// Adds the picked Characters that are not at the table yet.
    func addPicked() {
        let characterIds = selectionModel.selection.map(\.itemId)
        isPicking = false
        selectionModel.resetSelection(selectionIds: [])
        let current = tablePlayers()
        let updated = TablePlayerResolver.adding(characterIds: characterIds, to: current)
        guard updated != current else { return }
        update(updated)
    }

    func setEnabled(_ isEnabled: Bool, id: UUID) {
        var updated = tablePlayers()
        guard let index = updated.firstIndex(where: { $0.id == id }),
              updated[index].isEnabled != isEnabled else { return }
        updated[index].isEnabled = isEnabled
        update(updated)
    }

    func remove(id: UUID) {
        var updated = tablePlayers()
        guard updated.contains(where: { $0.id == id }) else { return }
        updated.removeAll { $0.id == id }
        update(updated)
    }

    func remove(atOffsets offsets: IndexSet) {
        let current = tablePlayers()
        let ids = Set(offsets.compactMap { current.indices.contains($0) ? current[$0].id : nil })
        guard !ids.isEmpty else { return }
        update(current.filter { !ids.contains($0.id) })
    }
}
