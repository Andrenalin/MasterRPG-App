// @copyright André Trettin

import CoreGraphics
import CoreRPG
import CoreTransferable
import Foundation
#if !os(tvOS)
import GeneratorRPG
#endif

struct LinkPdfModuleTransferable: LinkDataTransferable {
    let module: NetworkModules
    let itemId: UUID
    let entryId: UUID?
    let name: String
    let isMove: Bool

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.linkRepresentation)
    }
}

struct EditController: Sendable {
    @MainActor init(itemController: ItemController, linkController: LinkController, sheetController: SheetController, linkRegisterController: LinkRegisterController, tagController: TagController) {
        self.linkRegisterController = linkRegisterController
        self.tagController = tagController
        self.itemController = itemController
        self.editorModel = ItemEditorModel()
        let sheetEditorModel = SheetEditorModel(module: itemController.config.module)
        self.sheetRootModel = SheetRootModel(
            linkControllable: linkController,
            sheetControllable: sheetController,
            itemId: UUID(),
            isEditor: true,
            editorModel: sheetEditorModel
        )
        self.sheetEditorModel = sheetEditorModel
    }

    let itemController: ItemController
    let linkRegisterController: LinkRegisterController
    let tagController: TagController
    let editorModel: ItemEditorModel
    let sheetRootModel: SheetRootModel
    let sheetEditorModel: SheetEditorModel
}

extension EditController: EntryDataEditable {
    typealias Model = PdfModel
    
    var itemControllable: any ItemControllable { itemController }
    var fileUrlDataController: FileUrlDataController? { itemController.fileUrlDataController }

    public var linkModules: [NetworkModules] { [] }
    
    public func linkSelectionDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        SelectionRoute.selection
    }

    func create(name: String, content: String) -> PdfEntryModel {
        PdfEntryModel(id: UUID(), name: name, content: content, pageNumber: "", bounds: .zero)
    }
    
    func merge(itemId: UUID, entries: [PdfEntryModel], recoverEntries: [CoreRPG.ItemRowModel]?) -> [ItemRowModel] {
        []
    }
    
    public func quickEditorDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        SelectionRoute.selection
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
            name = String(localized: "Unnamed", bundle: .module).localizedString
        }
        return PdfEntryModel(id: itemId, name: name, content: content, pageNumber: page, bounds: bounds, displayState: 0)
    }
}

// MARK: - Apply extracted PDF content to a PdfModel using the EditController

#if !os(tvOS)
extension EditController {
    @MainActor func applyExtractedContent(_ content: PdfSummaryAnalysis, to itemId: UUID, selection: PdfPropertySelection) {
        // Update name if selected and (empty or forcing update)
        if selection.applyTitle {
            reset(name: content.title, itemId: itemId)
        }

        // Update description if selected and (empty or forcing update)
        if selection.applyDescription {
            reset(description: content.summary, itemId: itemId)
        }

        // Update tags if selected and (empty or forcing update)
        if selection.applyTags {
            reset(tags: content.tags, itemId: itemId)
        }

        // Create entries from sections if selected
        if selection.applySections && !content.sections.isEmpty {
            appendSectionsAsEntries(content.sections, to: itemId)
        }
    }

    @MainActor private func appendSectionsAsEntries(_ sections: [PdfSection], to itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }

        var newEntries: [PdfEntryModel] = []
        for section in sections {
            let pageNumberString = section.pageNumber.map { String($0) } ?? ""
            let entry = PdfEntryModel(
                id: UUID(),
                name: section.heading,
                content: section.summary,
                pageNumber: pageNumberString,
                bounds: .zero,
                displayState: 0
            )
            newEntries.append(entry)
        }

        item.entries.append(contentsOf: newEntries)
        
        save(updated: item, message: "Applied PDF sections as bookmarks".localizedString)
    }
}
#endif
