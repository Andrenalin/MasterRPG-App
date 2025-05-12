// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation

struct EditController: Sendable {
    @MainActor
    init(root: SpaceRoot, currentListItem: ItemRowTreeModel?, currentModel: (ModelType)?) {
        self.root = root
        self.editorModel = ItemEditorModel(currentListItem: currentListItem, currentModel: currentModel)
    }

    weak var root: SpaceRoot!
    let editorModel: ItemEditorModel
}

extension EditController: EditControllable {
    typealias Model = SpaceModel
    
    var itemControllable: any ItemControllable {
        root.itemController as (any ItemControllable)
    }

    var rootControllable: any RootControllable {
        root.rootControllable
    }
}

extension EditController {
    func reset(fileUrl: FileUrl, for itemId: UUID) async {
        let item = await itemId == model.id ? model : root.itemController.itemOrEmpty(for: itemId)
        item.fileUrl = fileUrl
        if await itemId == model.id {
            await save(with: "")
        } else {
            await root.itemController.replace(model: item, isInsert: false, shouldRepairLinks: false)
        }
    }
    
    private func resetFileUrl() async {
        await root.itemController.didDelete(fileUrl: model.fileUrl)
        await model.fileUrl = nil
    }

    func resetSpace(url: URL?) {
        Task { @MainActor in
            await resetSpace(url: url, for: model, undoSave: true)
        }
    }

    func resetSpace(url: URL?, into itemId: UUID) async {
        let item = await model.id == itemId ? model : root.itemController.item(for: itemId)?.copy()
        guard let item else { return }
        await resetSpace(url: url, for: item, undoSave: model.id == itemId)
    }

    private func resetSpace(url: URL?, for item: SpaceModel, undoSave: Bool) async {
        await root.itemController.didDelete(fileUrl: item.fileUrl)
        await resetURL(url: nil, on: item)
        guard let url else {
            if undoSave {
                await save(with: String(localized: "Remove Space").localizedString)
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
            await save(with: String(localized: "New Space").localizedString)
        } else {
            await root.itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)
        }
    }
    
    private func resetURL(url: FileUrl?, on item: SpaceModel) async {
        let saveTask = Task { @MainActor in
            item.fileUrl = url
        }
        await saveTask.value
    }
}
