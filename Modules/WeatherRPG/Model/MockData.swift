// @copyright André Trettin

import CoreRPG
import PhotoRPG
import RPGResources
import SwiftUI
import SwiftData

struct MockData: PreviewModifier {
    static let previewId = UUID()
    static let previewId2 = UUID()
    static let previewId3 = UUID()

    static var previewRoot: WeatherRootModel?
    
    func body(content: Content, context: ModelContainer) -> some View {
        content
            .modifier(MockRootViewModifier(modelContext: context.mainContext))
            .modelContainer(context)
    }
    static func makeSharedContext() async throws -> ModelContainer {
        let container = try! ModelContainer(
            for: WeatherDataModel.self, ItemDataModel.self, TagDataModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        
        let bundle = Resources.bundle
        guard let url = bundle.url(forResource: Resources.exampleFirstData, withExtension: "gmz") else {
            print("url nil ")
            return container
        }

        let root = WeatherRootModel.preview(container: container)
        let task = root.importController.importUrl(from: url)
        let _ = try await task.value
        let task4 = root.photoRoot.importControllable.importUrl(from: url)
        let _ = try await task4.value

        let model1 = ItemDataModel(
            id: previewId,
            module: .weather,
            name: "Mega Nice",
            information: "A lot of information about this item",
            category: .adventure,
            tags: ["Example", "Title", "Ouside"]
        )
        container.mainContext.insert(model1)
        let weather1 = WeatherDataModel(itemId: previewId)
        container.mainContext.insert(weather1)

        let model2 = ItemDataModel(
            id: previewId2,
            module: .weather,
            name: "Albert",
            information: "The is an example photo and the information is also set here",
            category: .character,
            tags: ["Player", "Mega", "Gnome"]
        )
        container.mainContext.insert(model2)
        let weather2 = WeatherDataModel(itemId: previewId2)
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
        let weather3 = WeatherDataModel(itemId: previewId)
        container.mainContext.insert(weather3)
        return container
    }
}

struct MockRootViewModifier: ViewModifier {
    init(modelContext: ModelContext) {
        self._root = State(wrappedValue: WeatherRootModel.preview(container: modelContext.container))
    }

    @Query(filter: #Predicate<ItemDataModel>{ $0.displayState == 0 }, sort: \ItemDataModel.name, animation: .smooth) private var items: [ItemDataModel]

    @State private var root: WeatherRootModel

    func body(content: Content) -> some View {
        content.environment(root)
            .environment(root.searchModel)
            .environment(root.listController.listModel)
            .environment(root.listDisplayModel)
            .environment(root.rootController)
            .environment(CacheItemListModel())
            .environment(DeviceRotationModel())
            .environment(TabTitleModel())
            .environment(root.photoRoot)
            .environment(linkRootController)
#if os(macOS)
            .frame(width: 800, height: 600)
#endif
            .onChange(of: items, initial: true) {
                Task {
                    await root.itemController.update(items: items.filter { $0.module == .weather })
                    await root.photoRoot.itemControllable.update(items: items.filter { $0.module == .photo })
                }
            }
    }
    
    var linkRootController: LinkRootController {
        LinkRootController(
            container: root.itemController.container,
            root: RootManager(adventureRoot: root, audioRoot: root, characterRoot: root, diceRoot: root, generatorRoot: root, mapRoot: root, pdfRoot: root, photoRoot: root.photoRoot, spaceRoot: root, tableRoot: root, weatherRoot: root)
        )
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}

extension WeatherRootModel {
    @MainActor public static func preview(container: ModelContainer) -> WeatherRootModel {
        if let root = MockData.previewRoot {
            return root
        }
        let newRoot = WeatherRootModel(modelContext: container.mainContext, photoRoot: .preview(container: container))
        MockData.previewRoot = newRoot
        return newRoot
    }
}
