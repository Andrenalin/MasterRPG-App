// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation

struct EditController: Sendable {
    @MainActor
    init(root: PdfRoot, itemController: ItemController, currentListItem: ItemRowTreeModel?, currentModel: (ModelType)?) {
        self.root = root
        self.itemController = itemController
        self.editorModel = ItemEditorModel(currentListItem: currentListItem, currentModel: currentModel)
    }

    weak var root: PdfRoot!
    let itemController: ItemController
    let editorModel: ItemEditorModel
}

extension EditController: EntryDataEditable {
    typealias Model = PdfModel

    var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }
    
    var rootControllable: any RootControllable {
        root.rootControllable
    }
}

extension EditController {
    func resetPdf(url: URL?) {
        Task { @MainActor in
            await resetPdf(url: url, for: model, undoSave: true)
        }
    }

    func resetPdf(url: URL?, into itemId: UUID) async {
        let item = await model.id == itemId ? model : itemController.item(for: itemId)?.copy()
        guard let item else { return }
        await resetPdf(url: url, for: item, undoSave: model.id == itemId)
    }

    private func resetPdf(url: URL?, for item: PdfModel, undoSave: Bool) async {
        await itemController.didDelete(fileUrl: item.fileUrl)
        await resetURL(url: nil, on: item)
        guard let url else {
            if undoSave {
                await save(with: String(localized: "Remove Pdf").localizedString)
            } else {
                await itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)
            }
            return
        }
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        if item.name.isEmpty {
            let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
            let name = url.lastPathComponent.replacingOccurrences(of: ext, with: "")
            item.name = name
        }
        let fileUrl = try? await root.fileUrlDataController.createFileUrl(fileId: item.id, url: url, module: itemController.itemDataModel.networkModule.token, useNewCloud: true)
        await resetURL(url: fileUrl, on: item)
        if undoSave {
            await save(with: String(localized: "New Pdf").localizedString)
        } else {
            await itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)
        }
    }
    
    private func resetURL(url: FileUrl?, on item: PdfModel) async {
        let saveTask = Task { @MainActor in
            item.fileUrl = url
        }
        await saveTask.value
    }
}

extension EditController {
    @MainActor
    func addBookmark(itemId: UUID, entry: PdfEntryModel) {
        let item: PdfModel
        if model.id == itemId {
            item = model
        } else {
            item = itemController.itemOrEmpty(for: itemId)
        }
        item.entries.append(entry)

        if model.id == itemId {
            save(with: String(localized: "Add bookmark").localizedString)
        } else {
            itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)
        }
    }
}
