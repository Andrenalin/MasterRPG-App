// @copyright André Trettin

import CoreRPG
import Foundation
import CoreData
import CoreGraphics

struct DataController: DataPersistenceControllable {
    @MainActor init(context: NSManagedObjectContext, batchContext: NSManagedObjectContext? = nil, token: String) {
            self.dataController = CoreDataController<PdfModel, RPGPdf>(context: context, batchContext: batchContext, relationshipKeyPaths: ["entries"])
            self.token = token
        }
        
        let dataController: CoreDataController<PdfModel, RPGPdf>
        let token: String
}

extension DataController: CoreDataSnapshotPersistable {
    // MARK: managed object -> snapshot (context queue)

    @Sendable
    func mapSnapshot(_ model: RPGPdf, token: String) -> PdfSnapshot {
        PdfSnapshot(
            id: model.uuid ?? UUID(),
            name: CRDT(wrappedValue: model.name ?? ""),
            description: CRDT(wrappedValue: model.information ?? ""),
            tags: CRDT(string: model.tags ?? "", defaultValue: tags(from: model.tags)),
            category: CRDT(string: model.pdfCategory ?? "", defaultValue: ItemListCategory.rules),
            displayState: Int(model.displayState),
            fileUrl: CRDTDataUpdate(wrappedValue: FileUrl(string: model.fileUrl ?? "", fileId: model.uuid ?? UUID(), module: token, unconvertedData: nil), update: CRDT(string: model.fileUrlUpdate ?? "", defaultValue: UUID())),
            entries: CRDTDataUpdate(wrappedValue: model.entriesModel.map { map($0) }, update: CRDT(string: model.entriesUpdate ?? "", defaultValue: UUID())),
            parentId: model.parentId
        )
    }
    
    // MARK: snapshot -> managed object (context queue)

    @Sendable
    func applySnapshot(_ snapshot: PdfSnapshot, into model: RPGPdf) {
        model.uuid <=> snapshot.id
        model.name <=> snapshot.name.rawValue
        model.information <=> snapshot.description.rawValue
        model.tags <=> snapshot.tags.rawValue
        model.pdfCategory <=> snapshot.category.rawValue
        model.displayState <=> Int32(snapshot.displayState)
        unequalSet(lhs: &model.fileUrlUpdate, rhs: snapshot.fileUrl.$update.rawValue) {
            model.fileUrl = snapshot.fileUrl.wrappedValue?.rawValue ?? ""
        }
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
    func makeModel(from snapshot: PdfSnapshot) -> PdfModel {
        snapshot.makeModel()
    }

    @MainActor
    func makeSnapshot(from model: PdfModel) -> PdfSnapshot {
        PdfSnapshot(model)
    }

    // MARK: - PdfEntryViewModel

    private func map(_ model: RPGPdfEntry) -> PdfEntryModel {
        PdfEntryModel(
            id: model.uuid ?? UUID(),
            name: model.name ?? "",
            content: model.content ?? "",
            pageNumber: model.pageLabel ?? "",
            bounds: JSONString.decode(text: model.bounds) ?? .zero
        )
    }

    private func map(_ viewModel: PdfEntryModel, into entry: RPGPdfEntry, index: Int) {
        entry.uuid = viewModel.id
        entry.name = viewModel.name
        entry.content = viewModel.content
        entry.pageLabel = viewModel.pageLabel
        entry.index = Int16(index)
        entry.bounds = JSONString.encode(value: viewModel.bounds) ?? ""
    }
}

