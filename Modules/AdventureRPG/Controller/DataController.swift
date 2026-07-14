// @copyright André Trettin

import CoreRPG
import Foundation
import CoreData

struct DataController: DataPersistenceControllable {
    @MainActor init(context: NSManagedObjectContext, batchContext: NSManagedObjectContext? = nil, token: String) {
        self.dataController = CoreDataController<AdventureModel, RPGAdventure>(context: context, batchContext: batchContext, relationshipKeyPaths: ["entries"])
        self.token = token
    }
    
    let dataController: CoreDataController<AdventureModel, RPGAdventure>
    let token: String
}

extension DataController: CoreDataSnapshotPersistable {
    // MARK: managed object -> snapshot (context queue)

    @Sendable
    func mapSnapshot(_ model: RPGAdventure, token: String) -> AdventureSnapshot {
        AdventureSnapshot(
            id: model.uuid ?? UUID(),
            name: CRDT(wrappedValue: model.name ?? ""),
            description: CRDT(wrappedValue: model.information ?? ""),
            tags: CRDT(string: model.tags ?? "", defaultValue: tags(from: model.tags)),
            category: CRDT(string: model.adventureCategory ?? "", defaultValue: ItemListCategory(rawValue: Int(model.adventureCategory ?? "1000") ?? 1000) ?? ItemListCategory.adventure),
            displayState: Int(model.displayState),
            photoId: CRDT(string: model.photoUUID ?? "", defaultValue: nil),
            diceId: model.diceId,
            entries: CRDTDataUpdate(wrappedValue: map(model.entriesModel), update: CRDT(string: model.entriesUpdate ?? "", defaultValue: UUID())),
            parentId: model.parentId,
            groupId: model.groupId
        )
    }

    // MARK: snapshot -> managed object (context queue)

    @Sendable
    func applySnapshot(_ snapshot: AdventureSnapshot, into model: RPGAdventure) {
        model.uuid <=> snapshot.id
        model.name <=> snapshot.name.rawValue
        model.information <=> snapshot.description.rawValue
        model.tags <=> snapshot.tags.rawValue
        model.adventureCategory <=> snapshot.category.rawValue
        model.displayState <=> Int32(snapshot.displayState)
        model.photoUUID <=> snapshot.photoId.rawValue
        model.diceId <=> snapshot.diceId
        unequalSet(lhs: &model.entriesUpdate, rhs: snapshot.entries.$update.rawValue) {
            let oldEntries = model.entriesModel
            let newEntries = snapshot.entries.wrappedValue.enumerated().map {
                let entry = model.entryOrNew(for: $1.id)
                self.map($1, into: entry, index: $0)
                return entry
            }
            model.entriesModel = newEntries
            // The inverse rule is Nullify, so entries dropped from the relationship
            // would remain as orphaned rows (locally and in CloudKit) — delete them.
            let keptEntries = Set(newEntries.map(ObjectIdentifier.init))
            for entry in oldEntries where !keptEntries.contains(ObjectIdentifier(entry)) {
                model.managedObjectContext?.delete(entry)
            }
        }
        model.parentId <=> snapshot.parentId
        model.groupId <=> snapshot.groupId
    }


    // MARK: model <-> snapshot (MainActor)

    @MainActor
    func makeModel(from snapshot: AdventureSnapshot) -> AdventureModel {
        snapshot.makeModel()
    }

    @MainActor
    func makeSnapshot(from model: AdventureModel) -> AdventureSnapshot {
        AdventureSnapshot(model)
    }

    // MARK: - EntryViewModel

    private func map(_ model: [RPGAdventureEntry]) -> [AdventureEntryModel] {
        model.sorted { $0.index < $1.index }.map { map($0) }
    }

    private func map(_ model: RPGAdventureEntry) -> AdventureEntryModel {
        AdventureEntryModel(
            id: model.uuid ?? UUID(),
            name: CRDT(string: model.name ?? "", defaultValue: ""),
            content: CRDT(string: model.content ?? "", defaultValue: ""),
            adventureId: CRDT(string: model.adventureUUID ?? "", defaultValue: nil),
            displayState: 0
        )
    }

    private func map(_ viewModel: AdventureEntryModel, into model: RPGAdventureEntry, index: Int) {
        model.uuid = viewModel.id
        model.name = viewModel.$name.rawValue
        model.content = viewModel.$content.rawValue
        model.adventureUUID = viewModel.$adventureId.rawValue
        model.index = Int16(index)
    }
}
