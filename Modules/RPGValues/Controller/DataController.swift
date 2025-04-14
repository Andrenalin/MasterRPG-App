// @copyright André Trettin

import AndrenalinKit
import Foundation
import CoreData

struct DataController: Sendable {
    @MainActor
    init(root: ValueRoot, context: NSManagedObjectContext, token: String) {
        self.root = root
        self.changeObserver = CoreDataChangeObserver()
        self.dataController = CoreDataController<ValueModel, RPGValue>(context: context)
        self.token = token

        changeObserver.observeCoreDataChanges(from: context, entity: RPGValue.entity(), handler: updateFromSync(deletedIds:insertedIds:updatedIds:))
    }
    
    weak var root: ValueRoot!
    let dataController: CoreDataController<ValueModel, RPGValue>
    var itemControllable: any ItemControllable {
        root.itemController
    }
    let changeObserver: CoreDataChangeObserver
    let token: String
}

extension DataController: CoreDataPersistable, DataPersistenceControllable {
    // MARK: model -> viewlmodel

    func mapViewModel(_ model: RPGValue, token: String) -> ValueModel {
        ValueModel(
            id: model.uuid ?? UUID(),
            name: CRDT(wrappedValue: model.name ?? ""),
            description: CRDT(wrappedValue: model.information ?? ""),
            tags: CRDT(string: model.tags ?? "", defaultValue: tags(from: model.tags)),
            category: CRDT(string: model.valueCategory ?? "", defaultValue: ItemListCategory.game),
            displayState: Int(model.displayState),
            photoId: CRDT(string: model.photoUUID ?? "", defaultValue: nil),
            photos: CRDTDataUpdate(wrappedValue: model.photoIds.compactMap { $0.uuid }, update: CRDT(string: model.photosUpdate ?? "", defaultValue: UUID())),
            entries: CRDTDataUpdate(wrappedValue: model.entriesModel.map { map($0) }, update: CRDT(string: model.entriesUpdate ?? "", defaultValue: UUID())),
            parentId: model.parentUUID
        )
    }

    // MARK: viewmodel -> model

    func mapModel(_ viewModel: ValueModel, into model: RPGValue) {
        model.uuid <=> viewModel.id
        model.name <=> viewModel.name_.rawValue
        model.information <=> viewModel.description_.rawValue
        model.tags <=> viewModel.tags_.rawValue
        model.valueCategory <=> viewModel.category_.rawValue
        model.displayState <=> Int32(viewModel.displayState)
        model.photoUUID <=> viewModel.photoId_.rawValue
        unequalSet(lhs: &model.photosUpdate, rhs: viewModel.photos_.$update.rawValue) {
            model.photoIds = viewModel.photos.enumerated().map {
                let entry = model.photoOrNew(for: $1)
                entry.uuid = $1
                entry.index = Int16($0)
                return entry
            }
        }
        unequalSet(lhs: &model.entriesUpdate, rhs: viewModel.entries_.$update.rawValue) {
            model.entriesModel = viewModel.entries.enumerated().map {
                let entry = model.entryOrNew(for: $1.id)
                self.map($1, into: entry, index: $0)
                return entry
            }
        }
        model.parentUUID <=> viewModel.parentId
    }

    // MARK: - ValueEntryModel

    private func map(_ model: [RPGValueEntry]) -> [ValueEntryModel] {
        model.sorted { $0.index < $1.index }.map { map($0) }
    }

    private func map(_ model: RPGValueEntry) -> ValueEntryModel {
        ValueEntryModel(
            id: model.uuid ?? UUID(),
            name: CRDT(wrappedValue: model.name ?? ""),
            type: CRDT(string: model.type ?? "", defaultValue: ValueEntryModel.ValueType.text),
            isGenerator: CRDT(string: model.isGenerator ?? "", defaultValue: false),
            value: CRDT(wrappedValue: model.value ?? ""),
            diceId: CRDT(string: model.diceUUID ?? "", defaultValue: nil),
            valueId: CRDT(string: model.valueUUID ?? "", defaultValue: nil)
        )
    }

    private func map(_ viewModel: ValueEntryModel, into valueEntry: RPGValueEntry, index: Int) {
        valueEntry.uuid <=> viewModel.id
        valueEntry.name <=> viewModel.$name.rawValue
        valueEntry.type <=> viewModel.$type.rawValue
        valueEntry.isGenerator <=> viewModel.$isGenerator.rawValue
        valueEntry.value <=> viewModel.$value.rawValue
        valueEntry.index <=> Int16(index)
        valueEntry.diceUUID <=> viewModel.$diceId.rawValue
        valueEntry.valueUUID <=> viewModel.$valueId.rawValue
    }
}
