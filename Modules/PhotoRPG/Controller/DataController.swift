// @copyright André Trettin

import CoreRPG
import Foundation
import CoreData

struct DataController: DataPersistenceControllable {
    @MainActor init(context: NSManagedObjectContext, batchContext: NSManagedObjectContext? = nil, token: String) {
            self.dataController = CoreDataController<PhotoModel, RPGPhoto>(context: context, batchContext: batchContext, relationshipKeyPaths: ["entries"])
            self.token = token
        }
        
        let dataController: CoreDataController<PhotoModel, RPGPhoto>
        let token: String
}

extension DataController: CoreDataPersistable {
    // MARK: model -> viewlmodel

    func mapViewModel(_ model: RPGPhoto, token: String) -> PhotoModel {
        PhotoModel(
            id: model.uuid ?? UUID(),
            name: CRDT(wrappedValue: model.name ?? ""),
            description: CRDT(wrappedValue: model.information ?? ""),
            tags: CRDT(string: model.tags ?? "", defaultValue: tags(from: model.tags)),
            category: CRDT(string: model.photoCategory ?? "", defaultValue: ItemListCategory.adventure),
            displayState: Int(model.displayState),
            degrees: CRDT(string: model.degrees ?? "", defaultValue: 0.0),
            fileUrl: CRDTDataUpdate(wrappedValue: FileUrl(string: model.fileUrl ?? "", fileId: model.uuid ?? UUID(), module: token, unconvertedData: nil), update: CRDT(string: model.fileUrlUpdate ?? "", defaultValue: UUID())),
            entries: CRDTDataUpdate(wrappedValue: model.entriesModel.map { map($0) }, update: CRDT(string: model.entriesUpdate ?? "", defaultValue: UUID())),
            parentId: model.parentId
        )
    }

    // MARK: viewmodel -> model

    func mapModel(_ viewModel: PhotoModel, into model: RPGPhoto) {
        model.uuid <=> viewModel.id
        model.name <=> viewModel.name_.rawValue
        model.information <=> viewModel.description_.rawValue
        model.tags <=> viewModel.tags_.rawValue
        model.photoCategory <=> viewModel.category_.rawValue
        model.displayState <=> Int32(viewModel.displayState)
        model.degrees <=> viewModel.degrees_.rawValue
        unequalSet(lhs: &model.fileUrlUpdate, rhs: viewModel.fileUrl_.$update.rawValue) {
            model.fileUrl = viewModel.fileUrl?.rawValue ?? ""
        }
        unequalSet(lhs: &model.entriesUpdate, rhs: viewModel.entries_.$update.rawValue) {
            let oldEntries = model.entriesModel
            let newEntries = viewModel.entries.enumerated().map {
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
        model.parentId <=> viewModel.parentId
    }

    // MARK: - PhotoEntryViewModel

    private func map(_ model: RPGPhotoEntry) -> PhotoEntryModel {
        PhotoEntryModel(
            id: model.uuid ?? UUID(),
            photoId: (model.photoUUID ?? model.uuid ?? UUID())
        )
    }

    private func map(_ viewModel: PhotoEntryModel, into entry: RPGPhotoEntry, index: Int) {
        entry.uuid = viewModel.id
        entry.photoUUID = viewModel.photoId
        entry.index = Int16(index)
    }
}
