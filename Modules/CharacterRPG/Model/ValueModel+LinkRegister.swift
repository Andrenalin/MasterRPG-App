// @copyright André Trettin

import CoreRPG
import Foundation

// MARK: - Link Register
// Split out of ValueModel.swift — see CODE_AUDIT_Character §9.9.

extension ValueModel: nonisolated ItemLinkRegistrable {
    @MainActor public var linkRegisterModels: [LinkRegisterModel] {
        changedLinkRegisterModels(oldValue: .empty).0
    }

    @MainActor public func changedLinkRegisterModels(oldValue: ValueModel) -> (added: [LinkRegisterModel], removed: [LinkRegisterModel]) {
        var added: [LinkRegisterModel] = []
        var removed: [LinkRegisterModel] = []

        if oldValue.photos != photos {
            let modelSource = ItemRowModel(itemId: id, typeId: .value)
            let addedPhotos = Set(photos).subtracting(Set(oldValue.photos))
            let removedPhotos = Set(oldValue.photos).subtracting(Set(photos))
            addedPhotos.forEach {
                added.append(LinkRegisterModel(name: "", source: modelSource, destination: ItemRowModel(itemId: $0, typeId: .photo)))
            }
            removedPhotos.forEach {
                removed.append(LinkRegisterModel(name: "", source: modelSource, destination: ItemRowModel(itemId: $0, typeId: .photo)))
            }
        }

        if oldValue.diceId != diceId {
            let modelSource = ItemRowModel(itemId: id, typeId: .value)
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
                    removed.append(contentsOf: linkRegisterModels(entry: oldEntry, nameChanged: oldEntry.name != newEntry.name, valueChanged: oldEntry.value != newEntry.value))
                    added.append(contentsOf: linkRegisterModels(entry: newEntry, nameChanged: oldEntry.name != newEntry.name, valueChanged: oldEntry.value != newEntry.value))
                }
            }
        }

        return (added, removed)
    }

    @MainActor func linkRegisterModels(entry: ValueEntryModel, nameChanged: Bool = true, valueChanged: Bool = true) -> [LinkRegisterModel] {
        let source = ItemRowModel(itemId: id, entryId: entry.id, typeId: .value)
        var total: [LinkRegisterModel] = []
        if nameChanged {
            total += LinkReplaceController.links(for: entry.name).map {
                LinkRegisterModel(link: $0, source: source)
            }
        }
        if valueChanged {
            total += LinkReplaceController.links(for: entry.value).map {
                LinkRegisterModel(link: $0, source: source)
            }
        }
        return total
    }
}
