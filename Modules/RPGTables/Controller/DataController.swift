// @copyright André Trettin

import AndrenalinKit
import Foundation
import CoreData

struct DataController: Sendable {
    @MainActor
    init(root: TableRootModel, context: NSManagedObjectContext, token: String) {
        self.root = root
        self.changeObserver = CoreDataChangeObserver()
        self.dataController = CoreDataController<TableModel, RPGTable>(context: context)
        self.token = token

        changeObserver.observeCoreDataChanges(from: context, entity: RPGTable.entity(), handler: updateFromSync(deletedIds:insertedIds:updatedIds:))
    }
    
    weak var root: TableRootModel!
    let dataController: CoreDataController<TableModel, RPGTable>
    var itemControllable: any ItemControllable {
        root.itemController
    }
    let changeObserver: CoreDataChangeObserver
    let token: String
}

extension DataController: CoreDataPersistable, DataPersistenceControllable, SyncDataControllable {
    var dataControllable: any CoreDataPersistable {
        self
    }
    
    // MARK: model -> viewlmodel

    func mapViewModel(_ model: RPGTable, token: String) -> TableModel {
        TableModel(
            id: model.uuid ?? UUID(),
            name: CRDT(wrappedValue: model.name ?? ""),
            description: CRDT(wrappedValue: model.information ?? ""),
            tags: CRDT(string: model.tags ?? "", defaultValue: tags(from: model.tags)),
            category: CRDT(string: model.tableCategory ?? "", defaultValue: ItemListCategory.rules),
            displayState: Int(model.displayState),
            tableType: CRDT(string: model.tableType ?? "", defaultValue: TableModel.TableType.list),
            diceId: CRDT(string: model.diceUUID ?? "", defaultValue: nil),
            entries: CRDTDataUpdate(wrappedValue: model.entriesModel.map { map($0) }, update: CRDT(string: model.entriesUpdate ?? "", defaultValue: UUID()))
        )
    }

    // MARK: viewmodel -> model

    func mapModel(_ viewModel: TableModel, into model: RPGTable) {
        model.uuid <=> viewModel.id
        model.name <=> viewModel.name_.rawValue
        model.information <=> viewModel.description_.rawValue
        model.tags <=> viewModel.tags_.rawValue
        model.tableCategory <=> viewModel.category_.rawValue
        model.displayState <=> Int32(viewModel.displayState)
        model.tableType <=> viewModel.tableType_.rawValue
        model.diceUUID <=> viewModel.diceId_.rawValue
        unequalSet(lhs: &model.entriesUpdate, rhs: viewModel.entries_.$update.rawValue) {
            model.entriesModel = viewModel.entries.enumerated().map {
                let entry = model.entryOrNew(for: $1.id)
                self.map($1, into: entry, index: $0)
                return entry
            }
        }
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
