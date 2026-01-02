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
    
    public func linkSelectionDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        SelectionModuleRoute.selection
    }

    public func linkSelectionDestination(for module: NetworkModules) -> any NavigationDestination {
        SelectionModuleRoute.selection
    }

    func create(name: String, content: String) -> PdfEntryModel {
        PdfEntryModel(id: UUID(), name: name, content: content, pageNumber: "", bounds: .zero)
    }
    
    func merge(modelId: UUID, entries: [PdfEntryModel], recoverEntries: [CoreRPG.ItemRowModel]?) async -> [ItemRowModel] {
        []
    }
}

extension EditController {
    @MainActor func addBookmark(itemId: UUID, entry: PdfEntryModel) {
        guard let editModel = editModel(for: itemId) else { return }
        editModel.entries.append(entry)
        save(updated: editModel, message: "Added Bookmark".localizedString)
    }
    
    func createBookmark(itemId: UUID, content: String, page: String, bounds: CGRect) -> PdfEntryModel {
        let name = String(content.split(separator: " ").first ?? "Unnamed")
        return PdfEntryModel(id: itemId, name: name, content: content, pageNumber: page, bounds: bounds, displayState: 0)        
    }

}
