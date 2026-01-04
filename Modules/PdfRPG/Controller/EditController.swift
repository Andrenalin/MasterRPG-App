// @copyright André Trettin

import CoreGraphics
import CoreRPG
import CoreTransferable
import Foundation

struct LinkPdfModuleTransferable: LinkDataTransferable {
    let module: NetworkModules
    let itemId: UUID
    let entryId: UUID?
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.linkRepresentation)
    }
}

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

extension EditController: EntryDataEditable {
    typealias Model = PdfModel
    
    var itemControllable: any ItemControllable { itemController }
    var fileUrlDataController: FileUrlDataController? { itemController.fileUrlDataController }

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
    
    func merge(itemId: UUID, entries: [PdfEntryModel], recoverEntries: [CoreRPG.ItemRowModel]?) async -> [ItemRowModel] {
        []
    }
}

extension EditController {
    @MainActor func addBookmark(itemId: UUID, entry: PdfEntryModel) {
        guard let item = editModel(for: itemId) else { return }
        item.entries.append(entry)
        save(updated: item, message: "Added Bookmark".localizedString)
    }
    
    func createBookmark(itemId: UUID, content: String, page: String, bounds: CGRect) -> PdfEntryModel {
        let name: String
        if let nameWord = content.split(separator: " ").first {
            name = String(nameWord)
        } else {
            name = String(localized: "Unnamed").localizedString
        }
        return PdfEntryModel(id: itemId, name: name, content: content, pageNumber: page, bounds: bounds, displayState: 0)
    }
}
