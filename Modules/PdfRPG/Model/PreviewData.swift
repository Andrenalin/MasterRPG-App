// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResources
import CoreGraphics

public extension PdfRootModel {
    static let previewSpaceId = PdfModel.previewId
    
    @MainActor
    static let preview: PdfRootModel = {
        let root = PdfRootModel(tagController: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root.rootController)
        root.setUp(context: nil, batchContext: nil, rootManager: realRootManager, linkRegisterController: LinkRegisterController(root: realRootManager))
        root.editController.setCurrentItem(to: .preview)
        return root
    }()
    
    @MainActor
    static let previewWithData: PdfRootModel = {
        let root = PdfRootModel.preview
        let itemController = root.itemController
        let importController = root.importController
        let editController = root.editController
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
    static func testRoot() -> PdfRootModel {
        let root = PdfRootModel(tagController: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, batchContext: nil, rootManager: rootManager, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root.rootController)
        root.setUp(context: nil, batchContext: nil, rootManager: realRootManager, linkRegisterController: LinkRegisterController(root: realRootManager))
        return root
    }
#endif
}

extension PdfRootModel: RootControllable {
    public var linkControllable: LinkControllable {
        linkController
    }
    
    public var gameExportControllable: any ExportControllable {
        exportController
    }
    public var gameImportControllable: any ImportControllable {
        importController
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
    static let preview: ItemController = PdfRootModel.preview.itemController
}

extension EditController {
    @MainActor
    static var preview: EditController = {
        let controller = PdfRootModel.preview.editController
        controller.setCurrentItem(to: .preview)
        return controller
    }()
}

extension GameController {
    @MainActor
    static var preview = PdfRootModel.preview.gameController
}

extension ImportController {
    @MainActor
    static var preview = PdfRootModel.preview.importController
}

extension ExportController {
    @MainActor
    static var preview = PdfRootModel.preview.exportController
}

extension ViewController {
    @MainActor
    static var preview = PdfRootModel.preview.viewController
}

extension LinkController {
    @MainActor
    static var preview = PdfRootModel.preview.linkController
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

