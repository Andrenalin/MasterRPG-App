// @copyright André Trettin

import AndrenalinKit
import DiceRPG
import Foundation
import PdfRPG
import PhotoRPG
import RPGResources
import TableRPG
import SwiftData

public extension CharacterRootModel {
    static let previewValueId = ValueModel.previewId

    @MainActor
    static let preview: CharacterRootModel = {
        let modelContainer = try! ModelContainer(for: TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let root = CharacterRootModel(container: modelContainer, diceRoot: .preview, pdfRoot: .preview, photoRoot: .preview, tableRoot: .preview)
        root.setUp(context: nil, rootControllable: root)
        root.itemController.replace(model: ValueModel.preview, isInsert: true, shouldRepairLinks: false)
        root.editController(type: .main).setCurrentItem(to: .preview)
        return root
    }()
    
    @MainActor
    static let previewWithData: CharacterRootModel = {
        let root = CharacterRootModel.preview
        let importController = root.importController
#if DEBUG
        Task.detached(priority: .userInitiated) {
            let bundle = Resources.bundle
            guard let url = bundle.url(forResource: Resources.exampleFirstData, withExtension: "gmz") else {
                print("url nil ")
                return
            }
            let task = importController.importUrl(from: url)
            let _ = try await task.value
        }
#endif
        return root
    }()
    
#if DEBUG
    @MainActor
    static func testRoot(diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel) -> CharacterRootModel {
        let modelContainer = try! ModelContainer(for: TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let root = CharacterRootModel(container: modelContainer, diceRoot: .preview, pdfRoot: .preview, photoRoot: .preview, tableRoot: .preview)
        root.setUp(context: nil, rootControllable: root)
        return root
    }
#endif

    @MainActor
    static let linkRegisterController = FakeLinkRegisterController()
}

extension CharacterRootModel: RootControllable {
    public var linkControllable: LinkControllable {
        linkController
    }

    @MainActor
    public var linkRegisterControllable: LinkRegisterControllable {
        CharacterRootModel.linkRegisterController
    }
    
    public var gameExportControllable: any ExportControllable {
        gameController.exportController
    }
    public var gameImportControllable: any ImportControllable {
        gameController.importController
    }
}

extension ItemRowTreeModel {
    @MainActor
    static let preview = ItemRowTreeModel(itemId: ValueModel.previewId, entryId: ValueEntryModel.previewId, typeId: .value)
}

extension ItemController {
    @MainActor
    static let preview = CharacterRootModel.preview.itemController
}

extension EditController {
    @MainActor
    static var preview: EditController = {
        let controller = CharacterRootModel.preview.editController(type: .main)
        controller.setCurrentItem(to: .preview)
        return controller
    }()
}

extension GameController {
    @MainActor
    static let preview = CharacterRootModel.preview.gameController
}

extension ImportController {
    @MainActor
    static let preview = CharacterRootModel.preview.importController
}

extension ExportController {
    @MainActor
    static let preview = CharacterRootModel.preview.exportController
}

extension ListController {
    @MainActor
    static let previewTabId = UUID()
    
    @MainActor
    static let preview = CharacterRootModel.preview.listController(tabId: previewTabId)
}

extension ListModel {
    @MainActor
    static var preview = ListController.preview.model
}

extension ViewController {
    @MainActor
    static let preview = CharacterRootModel.preview.viewController
}

extension LinkController {
    @MainActor
    static let preview = CharacterRootModel.preview.linkController
}

extension ValueModel {
    static let previewId = UUID(uuidString: "1527140F-0101-46C3-912E-B02FE0FF7696")!
    static let preview = ValueModel(id: previewId, name: "Andrenalin", description: "GameMaster forever", tags: ["Master", "Guide", "Coder"], category: .gameMaster, displayState: 0, photoId: PhotoRootModel.previewPhotoId, photos: [], entries: [.testEntryText, .testEntryNumber])
}

extension ValueEntryModel {
    static var previewId: UUID {
        UUID(uuidString: "5BD8F0AF-7B6D-4281-894F-C08B53E5D1B2") ?? UUID()
    }

    static var testEntryText: ValueEntryModel {
        ValueEntryModel(id: UUID(), name: "Character name", type: .text, value: "Andrenalin")
    }

    static var testEntryNumber: ValueEntryModel {
        ValueEntryModel(id: previewId, name: "Unverwundbartrank", type: .number, value: "1000")
    }
}
