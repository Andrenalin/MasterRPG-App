// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData
import UniformTypeIdentifiers

#if os(macOS)
internal import AppKit
#else
internal import UIKit
#endif

struct EditController {
    let fileUrlDataController: FileUrlDataController
}

extension EditController: EditControllable {
    typealias Model = PdfDataModel
}

// MARK: - Edit Data Model Properties
extension EditController {
    func createNewEntry(in model: PdfDataModel, childId: UUID) -> PdfEntryDataModel {
        PdfEntryDataModel(id: UUID(), index: Int16(model.entryModels.count), parentId: model.id, childId: childId, item: model)
    }
    
    func duplicate(model: PdfDataModel) {
        let newId = UUID()
        guard let actor = model.modelActor() else { return }
        let id = model.id
        Task.detached {
            await actor.setup(id: id)
            let fileUrl = try? await fileUrlDataController.duplicate(fileUrl: actor.fileUrl, for: newId)
            await actor.duplicate(url: fileUrl?.rawUrl)
            await actor.save()
        }
    }
            
    func removeItem(itemId: UUID, model: PdfDataModel) {
        model.withTransaction { modelContext in
            guard let item = PdfDataModel.model(modelContext: modelContext, id: itemId) else { return }
            
            let entry = model[itemId]
            model.entryModels.removeAll(where: { $0.childId == itemId })
            model.entryModels.enumerated().forEach { index, entry in
                entry.index = Int16(index)
            }
            modelContext.delete(entry)
            if model.category == .folder {
                item.parentId = nil
            }
            item.displayState = 0
        }
    }

    func update(model: PdfDataModel, name: String, information: String, category: ItemListCategory, tags: [String]) {
        model.withTransaction { modelContext in
            model.reset(name: name)
            model.reset(information: information)
            model.category = category
            model.tags = tags
        }
        
        updateTags(modelContext: model.modelContext)
    }
}

// MARK: - File Editor
extension EditController {
    func resetFile(url: URL?, in model: PdfDataModel) {
        guard let actor = model.modelActor() else { return }
        let id = model.id
        Task.detached {
            await actor.setup(id: id)
            await resetFile(url: url, id: id, actor: actor)
            await actor.save()
        }
    }
    
    private func resetFile(url: URL?, id: UUID, actor: DataModelActor) async {
        await fileUrlDataController.delete(await actor.fileUrl)
        guard let url else {
            await actor.update(url: url)
            return
        }
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        
        if await actor.name.isEmpty {
            let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
            let name = url.lastPathComponent.replacingOccurrences(of: ext, with: "")
            await actor.update(name: name)
        }
        let updatedFileUrl = try? await fileUrlDataController.createFileUrl(fileId: id, url: url, module: PdfDataModel.typeId.token, category: actor.category.title)
        await actor.update(url: updatedFileUrl?.rawUrl)
    }
}
