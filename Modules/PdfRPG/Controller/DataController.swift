// @copyright André Trettin

import CoreRPG
import Foundation
import CoreData
import CoreGraphics
import os.log

struct DataController: DataPersistenceControllable {
    @MainActor init(context: NSManagedObjectContext, token: String) {
            self.dataController = CoreDataController<PdfModel, RPGPdf>(context: context, relationshipKeyPaths: ["entries"])
            self.token = token
        }
        
        let dataController: CoreDataController<PdfModel, RPGPdf>
        let token: String
}

extension DataController: CoreDataSnapshotPersistable {
    // MARK: managed object -> snapshot (context queue)

    @Sendable
    func mapSnapshot(_ model: RPGPdf, token: String) -> PdfSnapshot {
        let id = repairedUuid(of: model, at: \.uuid)
        return PdfSnapshot(
            id: id,
            name: CRDT(wrappedValue: model.name ?? ""),
            description: CRDT(wrappedValue: model.information ?? ""),
            tags: CRDT(string: model.tags ?? "", defaultValue: tags(from: model.tags)),
            category: CRDT(string: model.pdfCategory ?? "", defaultValue: ItemListCategory.rules),
            displayState: Int(model.displayState),
            fileUrl: CRDTDataUpdate(wrappedValue: FileUrl(string: model.fileUrl ?? "", fileId: id, module: token, unconvertedData: nil), update: CRDT(string: model.fileUrlUpdate ?? "", defaultValue: UUID())),
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
        model.displayState <=> Int32(clamping: snapshot.displayState)
        unequalSet(lhs: &model.fileUrlUpdate, rhs: snapshot.fileUrl.$update.rawValue) {
            model.fileUrl = snapshot.fileUrl.wrappedValue?.rawValue ?? ""
        }
        unequalSet(lhs: &model.entriesUpdate, rhs: snapshot.entries.$update.rawValue) {
            model.entriesModel = model.syncEntries(
                incoming: snapshot.entries.wrappedValue,
                current: model.entriesModel,
                childId: { $0.id },
                map: { self.map($0, into: $1, index: $2) }
            )
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
            id: repairedUuid(of: model, at: \.uuid),
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
        entry.index = Int16(clamping: index)
        entry.bounds = JSONString.encode(value: viewModel.bounds) ?? ""
    }
}

