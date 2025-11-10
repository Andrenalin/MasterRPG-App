// @copyright André Trettin

import AndrenalinKit
import Foundation
import RPGResources
import CoreGraphics
import SwiftData

public extension PdfRoot {
    static let previewSpaceId = PdfModel.previewId
    
    @MainActor
    static let preview: PdfRoot = {
        let modelContainer = try! ModelContainer(for: TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let root = PdfRoot(container: modelContainer)
        root.setUp(context: nil, rootControllable: root)
        root.editController(type: .main).setCurrentItem(to: .preview)
        return root
    }()
    
    @MainActor
    static let previewWithData: PdfRoot = {
        let root = PdfRoot.preview
        let itemController = root.itemController
        let importController = root.importController
        let editController = root.editController(type: .main)
#if DEBUG
        Task.detached(priority: .userInitiated) {
            let bundle = Resources.bundle
            guard let url = bundle.url(forResource: Resources.exampleFirstData, withExtension: "gmz") else {
                print("url nil ")
                return
            }
            let task = importController.importUrl(from: url)
            let _ = try await task.value
            let saveTask = Task { @MainActor in
                editController.setCurrentItem(to: .previewWithData(from: itemController))
            }
            _ = await saveTask.result
        }
#endif
        return root
    }()
    
#if DEBUG
    @MainActor
    static func testRoot() -> PdfRoot {
        let modelContainer = try! ModelContainer(for: TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let root = PdfRoot(container: modelContainer)
        root.setUp(context: nil, rootControllable: root)
        return root
    }
#endif

    @MainActor
    static let linkRegisterController = FakeLinkRegisterController()
}

extension PdfRoot: RootControllable {
    public var linkControllable: LinkControllable {
        linkController
    }

    @MainActor
    public var linkRegisterControllable: LinkRegisterControllable {
        PdfRoot.linkRegisterController
    }
    
    public var gameExportControllable: any ExportControllable {
        gameController.exportController
    }
    public var gameImportControllable: any ImportControllable {
        gameController.importController
    }
}

extension ItemRowTreeModel {
    static let preview = ItemRowTreeModel(itemId: PdfModel.previewId, entryId: PdfEntryModel.previewId, typeId: .pdf)
    @MainActor
    static func previewWithData(from itemController: ItemController) -> ItemRowTreeModel {
        ItemRowTreeModel(itemId: itemController.itemDataModel.items[0], entryId: nil, typeId: .pdf)
    }
}

extension ItemController {
    @MainActor
    static let preview: ItemController = PdfRoot.preview.itemController
}

extension EditController {
    @MainActor
    static var preview: EditController = {
        let controller = PdfRoot.preview.editController(type: .main)
        controller.setCurrentItem(to: .preview)
        return controller
    }()
}

extension GameController {
    @MainActor
    static var preview = PdfRoot.preview.gameController
}

extension ImportController {
    @MainActor
    static var preview = PdfRoot.preview.importController
}

extension ExportController {
    @MainActor
    static var preview = PdfRoot.preview.exportController
}

extension ListController {
    @MainActor
    static let previewTabId = UUID()
    
    @MainActor
    static var preview = PdfRoot.preview.listController(tabId: previewTabId)
}

extension ListModel {
    @MainActor
    static var preview = ListController.preview.model
}

extension ViewController {
    @MainActor
    static var preview = PdfRoot.preview.viewController
}

extension LinkController {
    @MainActor
    static var preview = PdfRoot.preview.linkController
}

extension PdfModel {
    static let previewId = UUID(uuidString: "F5AC90DF-36F2-3152-B283-F0CF9D0BAC35")!

    @MainActor
    static let preview = PdfModel(id: PdfModel.previewId, name: "Rulebook", description: "Here is a rule book", tags: ["Fanatasy", "DS"], entries: [.preview])
}

extension PdfEntryModel {
    static let previewId = UUID(uuidString: "A5AC90DF-36F2-3152-B283-F0CF9D0BAC35")!
    
    @MainActor
    static let preview = PdfEntryModel(id: PdfModel.previewId, name: "First Bookmark", content: "Some Text from the pdf on a page", pageNumber: "3", bounds: .zero)
}

