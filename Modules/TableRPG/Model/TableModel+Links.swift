// @copyright André Trettin

import CoreRPG
import Foundation

// Split out of TableModel.swift. See CODE_AUDIT_Table §9.10.
extension TableModel: nonisolated ItemLinkRegistable {
    @MainActor public var linkRegisterModels: [LinkRegisterModel] {
        changedLinkRegisterModels(oldValue: .empty).0
    }

    @MainActor public func changedLinkRegisterModels(oldValue: TableModel) -> (added: [LinkRegisterModel], removed: [LinkRegisterModel]) {
        var added: [LinkRegisterModel] = []
        var removed: [LinkRegisterModel] = []

        if oldValue.diceId != diceId {
            let modelSource = ItemRowModel(itemId: id, typeId: .table)
            if let diceId = diceId {
                added.append(LinkRegisterModel(name: "", source: modelSource, destination: ItemRowModel(itemId: diceId, typeId: .dice)))
            }
            if let oldDiceId = oldValue.diceId {
                removed.append(LinkRegisterModel(name: "", source: modelSource, destination: ItemRowModel(itemId: oldDiceId, typeId: .dice)))
            }
        }

        if oldValue.entries != entries {
            let addedEntryIds = Set(entries.map(\.id)).subtracting(Set(oldValue.entries.map(\.id)))
            let removedEntryIds = Set(oldValue.entries.map(\.id)).subtracting(Set(entries.map(\.id)))
            addedEntryIds.forEach {
                added.append(contentsOf: linkRegisterModels(entry: self[$0]))
            }
            removedEntryIds.forEach {
                removed.append(contentsOf: linkRegisterModels(entry: oldValue[$0]))
            }
            let sameEntryIds = Set(entries.map(\.id)).intersection(Set(oldValue.entries.map(\.id)))
            sameEntryIds.forEach {
                let oldEntry = oldValue[$0]
                let newEntry = self[$0]
                if oldEntry != newEntry {
                    removed.append(contentsOf: linkRegisterModels(entry: oldEntry, valueChanged: oldEntry.content != newEntry.content))
                    added.append(contentsOf: linkRegisterModels(entry: newEntry, valueChanged: oldEntry.content != newEntry.content))
                }
            }
        }

        return (added, removed)
    }

    @MainActor func linkRegisterModels(entry: TableEntryModel, valueChanged: Bool = true) -> [LinkRegisterModel] {
        let source = ItemRowModel(itemId: id, entryId: entry.id, typeId: .table)
        var total: [LinkRegisterModel] = []
        if valueChanged {
            total += entry.links(for: entry.content).map {
                LinkRegisterModel(link: $0, source: source)
            }
        }
        return total
    }
}
