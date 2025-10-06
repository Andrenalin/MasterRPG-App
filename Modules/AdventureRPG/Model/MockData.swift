// @copyright André Trettin

import CoreRPG
import AudioRPG
import CharacterRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import RPGResources
import SpaceRPG
import TableRPG
import WeatherRPG
import SwiftUI
import SwiftData

struct MockData: PreviewModifier {
    static let previewId = UUID()
    static let previewId2 = UUID()
    static let previewId3 = UUID()

    static var previewRoot: AdventureRootModel?
    
    func body(content: Content, context: ModelContainer) -> some View {
        content
            .modifier(MockRootViewModifier(modelContext: context.mainContext))
            .modelContainer(context)
    }
    static func makeSharedContext() async throws -> ModelContainer {
        let container = try! ModelContainer(
            for: AdventureDataModel.self, AdventureEntryDataModel.self, ItemDataModel.self, TagDataModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        
        let bundle = Resources.bundle
        guard let url = bundle.url(forResource: Resources.exampleFirstData, withExtension: "gmz") else {
            print("url nil ")
            return container
        }

        let root = AdventureRootModel.preview(container: container)
        let task = root.importController.importUrl(from: url)
        let _ = try await task.value
        let task2 = root.diceRoot.importControllable.importUrl(from: url)
        let _ = try await task2.value
        let task3 = root.pdfRoot.importControllable.importUrl(from: url)
        let _ = try await task3.value
        let task4 = root.photoRoot.importControllable.importUrl(from: url)
        let _ = try await task4.value
        let task5 = root.tableRoot.importControllable.importUrl(from: url)
        let _ = try await task5.value
        let task6 = root.characterRoot.importControllable.importUrl(from: url)
        let _ = try await task6.value
        let task7 = root.weatherRoot.importControllable.importUrl(from: url)
        let _ = try await task7.value
        let task8 = root.audioRoot.importControllable.importUrl(from: url)
        let _ = try await task8.value
        let task9 = root.spaceRoot.importControllable.importUrl(from: url)
        let _ = try await task9.value

        let model1 = ItemDataModel(
            id: previewId,
            module: .adventure,
            name: "Mega Nice",
            information: "A lot of information about this item",
            category: .adventure,
            tags: ["Example", "Title", "Ouside"]
        )
        container.mainContext.insert(model1)
        
        let item1 = AdventureDataModel(itemId: previewId)
        container.mainContext.insert(item1)
        let entries = [
            AdventureEntryDataModel(itemId: previewId, entryId: UUID(), index: 0, name: "1", content: "Really only Cooper"),
            AdventureEntryDataModel(itemId: previewId, entryId: UUID(), index: 1, name: "2-9", content: "You found some Silver"),
            AdventureEntryDataModel(itemId: previewId, entryId: UUID(), index: 2, name: "10-15", content: "Some Gold and Silver"),
            AdventureEntryDataModel(itemId: previewId, entryId: UUID(), index: 3, name: "16-19", content: "Rich on Gold and Silver"),
            AdventureEntryDataModel(itemId: previewId, entryId: UUID(), index: 4, name: "20", content: "Mega Loot Gold- dold"),
        ]
        entries.forEach { container.mainContext.insert($0) }

        let model2 = ItemDataModel(
            id: previewId2,
            module: .adventure,
            name: "Albert",
            information: "The is an example photo and the information is also set here",
            category: .character,
            tags: ["Player", "Mega", "Gnome"]
        )
        container.mainContext.insert(model2)
        let weather2 = AdventureDataModel(itemId: previewId2)
        container.mainContext.insert(weather2)

        let model3 = ItemDataModel(
            id: previewId3,
            module: .adventure,
            name: "Zauberer",
            information: "A photo of a wizard.",
            category: .adventure,
            tags: ["NPC", "Wizward", "Schwarzmagier"]
        )
        container.mainContext.insert(model3)
        let weather3 = AdventureDataModel(itemId: previewId)
        container.mainContext.insert(weather3)
        return container
    }
}

struct MockRootViewModifier: ViewModifier {
    init(modelContext: ModelContext) {
        self._root = State(wrappedValue: AdventureRootModel.preview(container: modelContext.container))
    }

    @Query(filter: #Predicate<ItemDataModel>{ $0.displayState == 0 }, sort: \ItemDataModel.name, animation: .smooth) private var items: [ItemDataModel]

    @State private var root: AdventureRootModel

    func body(content: Content) -> some View {
        content.environment(root)
            .environment(root.searchModel)
            .environment(root.listController.listModel)
            .environment(root.listDisplayModel)
            .environment(root.rootController)
            .environment(CacheItemListModel())
            .environment(DeviceRotationModel())
            .environment(TabTitleModel())
            .environment(root.audioRoot)
            .environment(root.characterRoot)
            .environment(root.diceRoot)
            .environment(root.mapRoot)
            .environment(root.pdfRoot)
            .environment(root.photoRoot)
            .environment(root.spaceRoot)
            .environment(root.tableRoot)
            .environment(root.weatherRoot)
            .environment(linkRootController)
#if os(macOS)
            .frame(width: 800, height: 600)
#endif
            .onChange(of: items, initial: true) {
                Task {
                    await root.itemController.update(items: items.filter { $0.module == .adventure })
                    await root.audioRoot.itemControllable.update(items: items.filter { $0.module == .audio })
                    await root.characterRoot.itemControllable.update(items: items.filter {
                        $0.module == .value })
                    await root.diceRoot.itemControllable.update(items: items.filter { $0.module == .dice })
                    await root.mapRoot.itemControllable.update(items: items.filter { $0.module == .map })
                    await root.pdfRoot.itemControllable.update(items: items.filter { $0.module == .pdf })
                    await root.photoRoot.itemControllable.update(items: items.filter { $0.module == .photo })
                    await root.spaceRoot.itemControllable.update(items: items.filter { $0.module == .space })
                    await root.tableRoot.itemControllable.update(items: items.filter { $0.module == .table })
                    await root.weatherRoot.itemControllable.update(items: items.filter { $0.module == .weather })
                }
            }
    }
    
    var linkRootController: LinkRootController {
        LinkRootController(
            container: root.itemController.container,
            root: RootManager(adventureRoot: root, audioRoot: root.audioRoot, characterRoot: root.characterRoot, diceRoot: root.diceRoot, generatorRoot: root, mapRoot: root.mapRoot, pdfRoot: root.pdfRoot, photoRoot: root.photoRoot, spaceRoot: root.spaceRoot, tableRoot: root.tableRoot, weatherRoot: root.weatherRoot)
        )
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}

extension AdventureRootModel {
    @MainActor public static func preview(container: ModelContainer) -> AdventureRootModel {
        if let root = MockData.previewRoot {
            return root
        }
        let newRoot = AdventureRootModel(modelContext: container.mainContext, audioRoot: .preview(container: container), characterRoot: .preview(container: container), diceRoot: .preview(container: container), mapRoot: .preview(container: container), pdfRoot: .preview(container: container), photoRoot: .preview(container: container), spaceRoot: .preview(container: container), tableRoot: .preview(container: container), weatherRoot: .preview(container: container))
        MockData.previewRoot = newRoot
        return newRoot
    }
}
