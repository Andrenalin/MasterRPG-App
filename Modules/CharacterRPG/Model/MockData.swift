// @copyright André Trettin

import CoreRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG
import SwiftUI
import SwiftData

struct MockData: PreviewModifier {
    static let previewId = UUID()
    static let previewId2 = UUID()
    static let previewId3 = UUID()

    func body(content: Content, context: ModelContainer) -> some View {
        content
            .modifier(MockRootViewModifier(modelContext: context.mainContext))
            .modelContainer(context)
    }
    static func makeSharedContext() async throws -> ModelContainer {
        let container = try! ModelContainer(
            for: CharacterDataModel.self, CharacterEntryDataModel.self, ItemDataModel.self, TagDataModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        
        let model1 = ItemDataModel(
            id: previewId,
            module: .weather,
            name: "Mega Nice",
            information: "A lot of information about this item",
            category: .adventure,
            tags: ["Example", "Title", "Ouside"]
        )
        container.mainContext.insert(model1)
        
        let item1 = CharacterDataModel(itemId: previewId)
        container.mainContext.insert(item1)
        let entries = [
            CharacterEntryDataModel(itemId: previewId, entryId: UUID(), index: 0, name: "1", content: "Really only Cooper"),
            CharacterEntryDataModel(itemId: previewId, entryId: UUID(), index: 1, name: "2-9", content: "You found some Silver"),
            CharacterEntryDataModel(itemId: previewId, entryId: UUID(), index: 2, name: "10-15", content: "Some Gold and Silver"),
            CharacterEntryDataModel(itemId: previewId, entryId: UUID(), index: 3, name: "16-19", content: "Rich on Gold and Silver"),
            CharacterEntryDataModel(itemId: previewId, entryId: UUID(), index: 4, name: "20", content: "Mega Loot Gold- dold"),
        ]
        entries.forEach { container.mainContext.insert($0) }

        let model2 = ItemDataModel(
            id: previewId2,
            module: .weather,
            name: "Albert",
            information: "The is an example photo and the information is also set here",
            category: .character,
            tags: ["Player", "Mega", "Gnome"]
        )
        container.mainContext.insert(model2)
        let weather2 = CharacterDataModel(itemId: previewId2)
        container.mainContext.insert(weather2)

        let model3 = ItemDataModel(
            id: previewId3,
            module: .weather,
            name: "Zauberer",
            information: "A photo of a wizard.",
            category: .adventure,
            tags: ["NPC", "Wizward", "Schwarzmagier"]
        )
        container.mainContext.insert(model3)
        let weather3 = CharacterDataModel(itemId: previewId)
        container.mainContext.insert(weather3)
        return container
    }
}

struct MockRootViewModifier: ViewModifier {
    init(modelContext: ModelContext) {
        let diceRoot = DiceRootFactory.rootModel(modelContext: modelContext)
        self._root = State(wrappedValue: CharacterRootModel(modelContext: modelContext, diceRoot: diceRoot, pdfRoot: PdfRootFactory.rootModel(modelContext: modelContext), photoRoot: PhotoRootFactory.rootModel(modelContext: modelContext), tableRoot: TableRootFactory.rootModel(modelContext: modelContext, diceRoot: diceRoot)))
    }

    @State private var root: CharacterRootModel

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
            .environment(root.photoRoot)
            .environment(root.tableRoot)
#if os(macOS)
            .frame(width: 800, height: 600)
#endif
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}
