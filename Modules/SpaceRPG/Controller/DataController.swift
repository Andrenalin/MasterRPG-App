// @copyright André Trettin

import CoreRPG
import Foundation
import CoreData

struct DataController: DataPersistenceControllable {
    @MainActor init(context: NSManagedObjectContext, token: String) {
            self.dataController = CoreDataController<SpaceModel, RPGSpace>(context: context)
            self.token = token
        }
        
        let dataController: CoreDataController<SpaceModel, RPGSpace>
        let token: String
}

extension DataController: CoreDataPersistable {
    // MARK: model -> viewlmodel

    func mapViewModel(_ model: RPGSpace, token: String) -> SpaceModel {
        SpaceModel(
            id: model.uuid ?? UUID(),
            name: CRDT(wrappedValue: model.name ?? ""),
            description: CRDT(wrappedValue: model.information ?? ""),
            tags: CRDT(string: model.tags ?? "", defaultValue: tags(from: model.tags)),
            category: CRDT(string: model.spaceCategory ?? "", defaultValue: ItemListCategory.item),
            displayState: Int(model.displayState),
            degrees: CRDT(string: model.degrees ?? "", defaultValue: 0.0),
            fileUrl: CRDTDataUpdate(wrappedValue: FileUrl(string: model.fileUrl ?? "", fileId: model.uuid ?? UUID(), module: token, unconvertedData: nil), update: CRDT(string: model.fileUrlUpdate ?? "", defaultValue: UUID())),
            entries: CRDTDataUpdate(wrappedValue: model.entriesModel.map { map($0) }, update: CRDT(string: model.entriesUpdate ?? "", defaultValue: UUID())),
            parentId: model.parentId
        )
    }

    // MARK: viewmodel -> model

    func mapModel(_ viewModel: SpaceModel, into model: RPGSpace) {
        model.uuid <=> viewModel.id
        model.name <=> viewModel.name_.rawValue
        model.information <=> viewModel.description_.rawValue
        model.tags <=> viewModel.tags_.rawValue
        model.spaceCategory <=> viewModel.category_.rawValue
        model.displayState <=> Int32(viewModel.displayState)
        model.degrees <=> viewModel.degrees_.rawValue
        unequalSet(lhs: &model.fileUrlUpdate, rhs: viewModel.fileUrl_.$update.rawValue) {
            model.fileUrl = viewModel.fileUrl?.rawValue ?? ""
        }
        unequalSet(lhs: &model.entriesUpdate, rhs: viewModel.entries_.$update.rawValue) {
            model.entriesModel = viewModel.entries.enumerated().map {
                let entry = model.entryOrNew(for: $1.id)
                self.map($1, into: entry, index: $0)
                return entry
            }
        }
        model.parentId <=> viewModel.parentId
    }

    // MARK: - SpaceEntryViewModel

    private func map(_ model: RPGSpaceEntry) -> SpaceEntryModel {
        SpaceEntryModel(
            id: model.uuid ?? UUID(),
            spaceId: (model.spaceUUID ?? model.uuid ?? UUID())
        )
    }

    private func map(_ viewModel: SpaceEntryModel, into entry: RPGSpaceEntry, index: Int) {
        entry.uuid = viewModel.id
        entry.spaceUUID = viewModel.spaceId
        entry.index = Int16(index)
    }
}
