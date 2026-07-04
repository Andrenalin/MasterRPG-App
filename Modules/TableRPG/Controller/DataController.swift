// @copyright André Trettin

import CoreRPG
import Foundation
import CoreData

struct DataController: DataPersistenceControllable {
    @MainActor init(context: NSManagedObjectContext, batchContext: NSManagedObjectContext? = nil, token: String) {
        self.dataController = CoreDataController<TableModel, RPGTable>(context: context, batchContext: batchContext, relationshipKeyPaths: ["entries"])
        self.token = token
    }
    
    let dataController: CoreDataController<TableModel, RPGTable>
    let token: String
}

extension DataController: CoreDataSnapshotPersistable {
    // MARK: managed object -> snapshot (context queue)
    
    @Sendable
    func mapSnapshot(_ model: RPGTable, token: String) -> TableSnapshot {
        TableSnapshot(
            id: model.uuid ?? UUID(),
            name: CRDT(wrappedValue: model.name ?? ""),
            description: CRDT(wrappedValue: model.information ?? ""),
            tags: CRDT(string: model.tags ?? "", defaultValue: tags(from: model.tags)),
            category: CRDT(string: model.tableCategory ?? "", defaultValue: ItemListCategory.rules),
            displayState: Int(model.displayState),
            tableType: CRDT(string: model.tableType ?? "", defaultValue: TableModel.TableType.list),
            diceId: CRDT(string: model.diceUUID ?? "", defaultValue: nil),
            entries: CRDTDataUpdate(wrappedValue: model.entriesModel.map { map($0) }, update: CRDT(string: model.entriesUpdate ?? "", defaultValue: UUID())),
            parentId: model.parentId
        )
    }
    
    // MARK: snapshot -> managed object (context queue)
    
    @Sendable
    func applySnapshot(_ snapshot: TableSnapshot, into model: RPGTable) {
        model.uuid <=> snapshot.id
        model.name <=> snapshot.name.rawValue
        model.information <=> snapshot.description.rawValue
        model.tags <=> snapshot.tags.rawValue
        model.tableCategory <=> snapshot.category.rawValue
        model.displayState <=> Int32(snapshot.displayState)
        model.tableType <=> snapshot.tableType.rawValue
        model.diceUUID <=> snapshot.diceId.rawValue
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
    }
    

    // MARK: model <-> snapshot (MainActor)

    @MainActor
    func makeModel(from snapshot: TableSnapshot) -> TableModel {
        snapshot.makeModel()
    }

    @MainActor
    func makeSnapshot(from model: TableModel) -> TableSnapshot {
        TableSnapshot(model)
    }

    // MARK: - TableEntryViewModel
    
    private func map(_ model: RPGTableEntry) -> TableEntryModel {
        TableEntryModel(
            id: model.uuid ?? UUID(),
            name: model.name ?? "",
            content: model.content ?? ""
        )
    }
    
    private func map(_ viewModel: TableEntryModel, into entry: RPGTableEntry, index: Int) {
        entry.uuid = viewModel.id
        entry.content = viewModel.content
        entry.name = viewModel.name
        entry.index = Int16(index)
    }
}
