// @copyright André Trettin

import CoreRPG
import Foundation
import CoreGraphics

public extension PdfRootModel {
    static let previewPdfId = PdfModel.previewId
    static let previewSpaceId = PdfModel.previewId
    
    @MainActor
    static var preview: PdfRootModel { previewFixture() }

    @MainActor
    internal static func previewFixture(
        models: [PdfModel] = PdfModel.previewFixtures
    ) -> PdfRootModel {
        let root = PdfRootModel(tagController: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root.rootController)
        root.setUp(context: nil, rootManager: realRootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: realRootManager))
        for model in models {
            root.itemController.replace(model: model, isInsert: true)
        }
        root.editController.setCurrentItem(to: .preview)
        return root
    }
    
    @MainActor
    static var previewWithData: PdfRootModel { previewFixture() }
    
#if DEBUG
    @MainActor
    static func testRoot() -> PdfRootModel {
        let root = PdfRootModel(tagController: .preview)
        let rootManager = RootManager.preview(fake: ItemRootController.fake)
        root.setUp(context: nil, rootManager: rootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: rootManager))
        let realRootManager = RootManager.preview(fake: root.rootController)
        root.setUp(context: nil, rootManager: realRootManager, adventureRootControllable: root, linkRegisterController: LinkRegisterController(root: realRootManager))
        return root
    }
#endif
}

@MainActor
extension PdfRootModel: RootExportControllable {
    public var linkControllable: LinkControllable {
        linkController
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
    nonisolated static let previewId = UUID.fixture("F5AC90DF-36F2-3152-B283-F0CF9D0BAC35")
    nonisolated static let previewEmptyId = UUID(uuid: (0xB2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))

    @MainActor
    static var preview: PdfModel {
        PdfModel(
            id: PdfModel.previewId,
            name: "Game Master Rulebook",
            description: "A real PDF fixture with bookmarks and extractable text.",
            tags: ["Fantasy", "Rules"],
            fileUrl: PreviewAssetFixture.fileUrl(
                .pdf,
                fileId: previewId,
                module: NetworkModules.pdf.token
            ),
            entries: [.preview]
        )
    }

    /// A deterministic PDF record without a file or bookmarks.
    @MainActor
    static let previewEmpty = PdfModel(
        id: previewEmptyId,
        name: "Empty Rulebook",
        description: "A PDF fixture with no imported document.",
        tags: ["Preview"],
        entries: []
    )

    @MainActor
    static var previewFixtures: [PdfModel] {
        [preview, previewEmpty]
    }
}

extension PdfEntryModel {
    nonisolated static let previewId = UUID.fixture("A5AC90DF-36F2-3152-B283-F0CF9D0BAC35")
    
    @MainActor
    static let preview = PdfEntryModel(id: previewId, name: "First Bookmark", content: "A bookmarked rule from the example PDF.", pageNumber: "1", bounds: .zero)
}

private extension UUID {
    nonisolated static func fixture(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else {
            preconditionFailure("Invalid deterministic preview UUID: \(value)")
        }
        return id
    }
}
