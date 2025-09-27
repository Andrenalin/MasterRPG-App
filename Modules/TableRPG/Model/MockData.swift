// @copyright André Trettin

import CoreRPG
import DiceRPG
import PdfRPG
import SwiftUI
import SwiftData

struct MockData: PreviewModifier {
    static let previewId = UUID()
    static let previewId2 = UUID()
    static let previewId3 = UUID()

    static let previewEntryId = UUID()
    static let previewEntryId2 = UUID()
    static let previewEntryId3 = UUID()

    func body(content: Content, context: ModelContainer) -> some View {
        content
            .modifier(MockRootViewModifier(modelContext: context.mainContext))
            .modelContainer(context)
    }
    static func makeSharedContext() async throws -> ModelContainer {
        let container = try! ModelContainer(
            for: TableDataModel.self, TableEntryDataModel.self, ItemDataModel.self, LinkDataModel.self, TagDataModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        
        let entries = [
            TableEntryDataModel(itemId: previewId, entryId: previewEntryId, index: 0, name: "1", content: "Really only Cooper"),
            TableEntryDataModel(itemId: previewId, entryId: previewEntryId2, index: 1, name: "2-9", content: "You found some Silver"),
            TableEntryDataModel(itemId: previewId, entryId: previewEntryId3, index: 2, name: "10-15", content: "Some Gold and Silver"),
            TableEntryDataModel(itemId: previewId, entryId: UUID(), index: 3, name: "16-19", content: "Rich on Gold and Silver"),
            TableEntryDataModel(itemId: previewId, entryId: UUID(), index: 4, name: "20", content: "Mega Loot Gold- dold"),
        ]

        let item1 = TableDataModel(itemId: previewId, diceId: nil, entries: entries)
        container.mainContext.insert(item1)
        
        let model1 = ItemDataModel(
            id: previewId,
            module: .table,
            name: "Mega Nice",
            information: "A lot of information about this item",
            category: .adventure,
            tags: ["Example", "Title", "Ouside"]
        )
        container.mainContext.insert(model1)

        let item2 = TableDataModel(itemId: previewId2)
        container.mainContext.insert(item2)
        let model2 = ItemDataModel(
            id: previewId2,
            module: .table,
            name: "Albert",
            information: "The is an example photo and the information is also set here",
            category: .character,
            tags: ["Player", "Mega", "Gnome"]
        )
        container.mainContext.insert(model2)

        let item3 = TableDataModel(itemId: previewId)
        container.mainContext.insert(item3)
        let model3 = ItemDataModel(
            id: previewId3,
            module: .table,
            name: "Zauberer",
            information: "A photo of a wizard.",
            category: .adventure,
            tags: ["NPC", "Wizward", "Schwarzmagier"]
        )
        container.mainContext.insert(model3)
        do {
            try container.mainContext.save()
        } catch {
            print("Save error \(error.localizedDescription)")
        }
        return container
    }
}

struct MockRootViewModifier: ViewModifier {
    init(modelContext: ModelContext) {
        self._root = State(wrappedValue: TableRootModel(modelContext: modelContext, diceRoot: DiceRootFactory.rootModel(modelContext: modelContext), pdfRoot: PdfRootFactory.rootModel(modelContext: modelContext)))
    }

    @State private var root: TableRootModel

    func body(content: Content) -> some View {
        content.environment(root)
            .environment(root.searchModel)
            .environment(root.listController.listModel)
            .environment(root.listDisplayModel)
            .environment(root.rootController)
            .environment(CacheItemListModel())
            .environment(DeviceRotationModel())
            .environment(TabTitleModel())
            .environment(root.diceRoot)
            .environment(root.pdfRoot)
            .environment(linkRootController)
#if os(macOS)
            .frame(width: 800, height: 600)
#endif
    }
    
    var linkRootController: LinkRootController {
        LinkRootController(container: root.itemController.container, root: RootManager(adventureRoot: root, audioRoot: root, characterRoot: root, diceRoot: root.diceRoot, mapRoot: root, pdfRoot: root.pdfRoot, photoRoot: root, spaceRoot: root, tableRoot: root, weatherRoot: root))
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}
