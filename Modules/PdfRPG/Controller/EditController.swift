// @copyright André Trettin

import CoreGraphics
import CoreRPG
import CoreTransferable
import Foundation
import Observation

struct EditController: Sendable {
    @MainActor init(itemController: ItemController, linkRegisterControllable: LinkRegisterControllable) {
        self.linkRegisterControllable = linkRegisterControllable
        self.itemController = itemController
        self.editorModel = ItemEditorModel()
    }

    let itemController: ItemController
    let linkRegisterControllable: any LinkRegisterControllable
    let editorModel: ItemEditorModel
}

struct LinkPdfModuleTransferable: LinkDataTransferable {
    let module: NetworkModules
    let itemId: UUID
    let entryId: UUID?
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.linkRepresentation)
    }
}

extension EditController: EntryDataEditable {
    typealias Model = PdfModel
    
    var itemControllable: any ItemControllable {
        itemController
    }
    
    var fileUrlDataController: FileUrlDataController? {
        itemControllable.fileUrlDataController
    }
    
    public var linkModules: [NetworkModules] { [] }
    
    public func linkSelectionDestination(for entryId: UUID) -> any NavigationDestination {
        SelectionModuleRoute.selection
    }

    public func linkSelectionDestination(for module: NetworkModules) -> any NavigationDestination {
        SelectionModuleRoute.selection
    }

    func create(name: String, content: String) -> PdfEntryModel {
        PdfEntryModel(id: UUID(), name: name, content: content, pageNumber: "", bounds: .zero)
    }
    
    func merge(entries: [PdfEntryModel], recoverEntries: [CoreRPG.ItemRowModel]?) async -> [ItemRowModel] {
        []
    }
}

extension EditController {
    func reset(fileUrl: FileUrl, for itemId: UUID) async {
        let item = await itemId == model.id ? model : itemController.itemOrEmpty(for: itemId).copy()
        item.fileUrl = fileUrl
        if await itemId == model.id {
            await save(with: "")
        } else {
            await itemController.replace(model: item, isInsert: false, shouldRepairLinks: false)
        }
    }

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
        guard let fileUrlDataController else { return }
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
        let fileUrl = try? await fileUrlDataController.createFileUrl(fileId: item.id, url: url, module: itemController.config.module.token, category: item.category.title)
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
    
    func createBookmark(itemId: UUID, content: String, page: String, bounds: CGRect) -> PdfEntryModel {
        let name = String(content.split(separator: " ").first ?? "Unnamed")
        return PdfEntryModel(id: itemId, name: name, content: content, pageNumber: page, bounds: bounds, displayState: 0)        
    }

}
