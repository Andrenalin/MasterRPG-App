// @copyright André Trettin

import CoreRPG
import DiceRPG
import PdfRPG
import RPGResources
import SwiftUI
import SwiftData

struct MockData: PreviewModifier {
    static let previewId = UUID()
    static let previewId2 = UUID()
    static let previewId3 = UUID()

    static let previewEntryId = UUID()
    static let previewEntryId2 = UUID()
    static let previewEntryId3 = UUID()

    static var previewRoot: TableRootModel?
    
    func body(content: Content, context: ModelContainer) -> some View {
        content
            .modifier(MockRootViewModifier(modelContext: context.mainContext))
            .modelContainer(context)
    }
    static func makeSharedContext() async throws -> ModelContainer {
        let container = try! ModelContainer(
            for: TableDataModel.self, TableEntryDataModel.self, DiceDataModel.self, PdfDataModel.self, ItemDataModel.self, LinkDataModel.self, TagDataModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        
        let bundle = Resources.bundle
        guard let url = bundle.url(forResource: Resources.exampleFirstData, withExtension: "gmz") else {
            print("url nil ")
            return container
        }

        let root = TableRootModel.preview(container: container)        
        let task = root.importController.importUrl(from: url)
        let _ = try await task.value
        let task2 = root.diceRoot.importControllable.importUrl(from: url)
        let _ = try await task2.value
        let task3 = root.pdfRoot.importControllable.importUrl(from: url)
        let _ = try await task3.value

        
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
        self._root = State(wrappedValue: TableRootModel.preview(container: modelContext.container))
    }

    @Query(filter: #Predicate<ItemDataModel>{ $0.displayState == 0 }, sort: \ItemDataModel.name, animation: .smooth) private var items: [ItemDataModel]

    @State private var root: TableRootModel

    func body(content: Content) -> some View {
        content
            .environment(root)
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
            .onChange(of: items, initial: true) {
                Task {
                    await root.itemController.update(items: items.filter { $0.module == .table })
                    await root.diceRoot.itemControllable.update(items: items.filter { $0.module == .dice })
                    await root.pdfRoot.itemControllable.update(items: items.filter { $0.module == .pdf })
                }
            }
    }
    
    var linkRootController: LinkRootController {
        LinkRootController(
            container: root.itemController.container,
            root: RootManager(adventureRoot: root, audioRoot: root, characterRoot: root, diceRoot: root.diceRoot, generatorRoot: root, mapRoot: root, pdfRoot: root.pdfRoot, photoRoot: root, spaceRoot: root, tableRoot: root, weatherRoot: root)
        )
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}

extension TableRootModel {
    @MainActor public static func preview(container: ModelContainer) -> TableRootModel {
        if let root = MockData.previewRoot {
            return root
        }
        let newRoot = TableRootModel(modelContext: container.mainContext, diceRoot: DiceRootModel.preview(container: container), pdfRoot: PdfRootModel.preview(container: container))
        MockData.previewRoot = newRoot
        return newRoot
    }
}
