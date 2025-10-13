// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation

struct EditController: Sendable {
    @MainActor
    init(root: AudioRoot, fileUrlDataController: FileUrlDataController, currentListItem: ItemRowTreeModel?, currentModel: (ModelType)?) {
        self.root = root
        self.fileUrlDataController = fileUrlDataController
        self.editorModel = ItemEditorModel(currentListItem: currentListItem, currentModel: currentModel)
    }

    weak var root: AudioRoot!
    let fileUrlDataController: FileUrlDataController?
    let editorModel: ItemEditorModel
}

extension EditController: EditControllable {
    typealias Model = AudioModel
    
    var itemControllable: any ItemControllable {
        root.itemController as (any ItemControllable)
    }

    var rootControllable: any RootControllable {
        root.rootControllable
    }
}

extension EditController {
    @MainActor func reset(category: ItemListCategory) {
        guard model.category != category else { return }
        let oldCategory = model.category
        let oldFileUrl = model.fileUrl
        model.category = category
        let saveModel = model
        Task { @MainActor in
            let newFileUrl = await root.fileUrlDataController.move(fileUrl: oldFileUrl, from: oldCategory, to: category)
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
        Task { @MainActor in
            let newFileUrl = await root.fileUrlDataController.move(fileUrl: oldFileUrl, from: oldName, to: saveModel.name)
            if let newFileUrl {
                saveModel.fileUrl = newFileUrl
            }
            save(with: String(localized: "Typing").localizedString)
        }
    }
    
    func reset(fileUrl: FileUrl, for itemId: UUID) async {
        let item = await itemId == model.id ? model : root.itemController.itemOrEmpty(for: itemId).copy()
        item.fileUrl = fileUrl
        if await itemId == model.id {
            await save(with: "")
        } else {
            await root.itemController.replace(model: item, isInsert: false, shouldRepairLinks: false)
        }
    }
}

extension EditController {
    func resetAudio(url: URL?) {
        Task { @MainActor in
            await resetAudio(url: url, for: model, undoSave: true)
        }
    }

    func resetAudio(url: URL?, into itemId: UUID) async {
        let item = await model.id == itemId ? model : root.itemController.item(for: itemId)?.copy()
        guard let item else { return }
        await resetAudio(url: url, for: item, undoSave: model.id == itemId)
    }

    private func resetAudio(url: URL?, for item: AudioModel, undoSave: Bool) async {
        await root.itemController.didDelete(fileUrl: item.fileUrl)
        await resetURL(url: nil, on: item)
        guard let url else {
            if undoSave {
                await save(with: String(localized: "Remove Audio").localizedString)
            } else {
                await root.itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)
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
        let fileUrl = try? await root.fileUrlDataController.createFileUrl(fileId: item.id, url: url, module: root.itemController.itemDataModel.networkModule.token, category: item.category.title)
        await resetURL(url: fileUrl, on: item)
        if undoSave {
            let saveTask = Task { @MainActor in
                save(with: String(localized: "New Audio").localizedString)
            }
            _ = await saveTask.result
        } else {
            await root.itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)
        }
    }
    
    private func resetURL(url: FileUrl?, on item: AudioModel) async {
        let saveTask = Task { @MainActor in
            item.fileUrl = url
        }
        await saveTask.value
    }
}
