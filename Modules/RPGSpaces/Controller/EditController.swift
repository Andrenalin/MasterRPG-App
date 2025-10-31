// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation

struct EditController: Sendable {
    @MainActor
    init(itemController: ItemController, linkRegisterControllable: LinkRegisterControllable, currentListItem: ItemRowTreeModel?, currentModel: (ModelType)?) {
        self.linkRegisterControllable = linkRegisterControllable
        self.itemController = itemController
        self.editorModel = ItemEditorModel(currentListItem: currentListItem, currentModel: currentModel)
    }

    let itemController: ItemController
    let linkRegisterControllable: any LinkRegisterControllable
    let editorModel: ItemEditorModel
}

extension EditController: EditControllable {
    typealias Model = SpaceModel
    
    var itemControllable: any ItemControllable {
        itemController
    }
    
    var fileUrlDataController: FileUrlDataController? {
        itemControllable.fileUrlDataController
    }
}

extension EditController {
    @MainActor func reset(category: ItemListCategory) {
        guard model.category != category else { return }
        let oldCategory = model.category
        let oldFileUrl = model.fileUrl
        model.category = category
        let saveModel = model
        guard let fileUrlDataController else {
            save(with: String(localized: "Change to \(category.title)").localizedString)
            return
        }
        Task { @MainActor in
            let newFileUrl = await fileUrlDataController.move(fileUrl: oldFileUrl, from: oldCategory, to: category)
            if let newFileUrl {
                saveModel.fileUrl = newFileUrl
            }
            save(with: String(localized: "Change to \(category.title)").localizedString)
        }
    }

    @MainActor func reset(name: String) {
        guard model.name != name else { return }
        let oldName = model.name
        let oldFileUrl = model.fileUrl
        model.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        editorModel.cacheItemListModel.reset(cacheType: .name, itemId: model.id, text: model.name.markDownText())
        let saveModel = model
        guard let fileUrlDataController else {
            save(with: String(localized: "Typing").localizedString)
            return
        }
        Task { @MainActor in
            let newFileUrl = await fileUrlDataController.move(fileUrl: oldFileUrl, from: oldName, to: saveModel.name)
            if let newFileUrl {
                saveModel.fileUrl = newFileUrl
            }
            save(with: String(localized: "Typing").localizedString)
        }
    }
    
    func reset(fileUrl: FileUrl, for itemId: UUID) async {
        let item = await itemId == model.id ? model : itemController.itemOrEmpty(for: itemId).copy()
        item.fileUrl = fileUrl
        if await itemId == model.id {
            await save(with: "")
        } else {
            await itemController.replace(model: item, isInsert: false, shouldRepairLinks: false)
        }
    }
}

extension EditController {    
    private func resetFileUrl() async {
        await itemController.didDelete(fileUrl: model.fileUrl)
        await model.fileUrl = nil
    }

    func resetSpace(url: URL?) {
        Task { @MainActor in
            await resetSpace(url: url, for: model, undoSave: true)
        }
    }

    func resetSpace(url: URL?, into itemId: UUID) async {
        let item = await model.id == itemId ? model : itemController.item(for: itemId)?.copy()
        guard let item else { return }
        await resetSpace(url: url, for: item, undoSave: model.id == itemId)
    }

    private func resetSpace(url: URL?, for item: SpaceModel, undoSave: Bool) async {
        guard let fileUrlDataController else { return }
        await itemController.didDelete(fileUrl: item.fileUrl)
        await resetURL(url: nil, on: item)
        guard let url else {
            if undoSave {
                await save(with: String(localized: "Remove Space").localizedString)
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
        let fileUrl = try? await fileUrlDataController.createFileUrl(fileId: item.id, url: url, module: itemController.itemDataModel.networkModule.token, category: item.category.title)
        await resetURL(url: fileUrl, on: item)
        if undoSave {
            await save(with: String(localized: "New Space").localizedString)
        } else {
            await itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)
        }
    }
    
    private func resetURL(url: FileUrl?, on item: SpaceModel) async {
        let saveTask = Task { @MainActor in
            item.fileUrl = url
        }
        await saveTask.value
    }
}
