// @copyright André Trettin

import CoreRPG
import AdventureRPG
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
    static var previewRoot: GameRootController?
    
    func body(content: Content, context: ModelContainer) -> some View {
        content
            .modifier(MockRootViewModifier(modelContext: context.mainContext))
            .modelContainer(context)
    }
    static func makeSharedContext() async throws -> ModelContainer {
        let container = try! ModelContainer(
            for: AdventureDataModel.self, MapDataModel.self, CharacterDataModel.self, TableDataModel.self, PdfDataModel.self, DiceDataModel.self, LinkDataModel.self, ItemDataModel.self, TagDataModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        
        let bundle = Resources.bundle
        guard let url = bundle.url(forResource: Resources.exampleFirstData, withExtension: "gmz") else {
            print("url nil ")
            return container
        }
        
        let rootManager = RootManager(
            adventureRoot: AdventureRootModel.preview(container: container), audioRoot: AudioRootModel.preview(container: container), characterRoot: CharacterRootModel.preview(container: container), diceRoot: DiceRootModel.preview(container: container), generatorRoot: AdventureRootModel.preview(container: container), mapRoot: MapRootModel.preview(container: container), pdfRoot: PdfRootModel.preview(container: container), photoRoot: PhotoRootModel.preview(container: container), spaceRoot: SpaceRootModel.preview(container: container), tableRoot: TableRootModel.preview(container: container), weatherRoot: WeatherRootModel.preview(container: container)
        )

        let root = GameRootController(root: rootManager, adventureRoot: AdventureRootModel.preview(container: container), audioRoot: AudioRootModel.preview(container: container), characterRoot: CharacterRootModel.preview(container: container), diceRoot: DiceRootModel.preview(container: container), mapRoot: MapRootModel.preview(container: container), pdfRoot: PdfRootModel.preview(container: container), photoRoot: PhotoRootModel.preview(container: container), spaceRoot: SpaceRootModel.preview(container: container), tableRoot: TableRootModel.preview(container: container), weatherRoot: WeatherRootModel.preview(container: container))
        let task = root.adventureRoot.importControllable.importUrl(from: url)
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
        return container
    }
}

struct MockRootViewModifier: ViewModifier {
    init(modelContext: ModelContext) {
        self._root = State(wrappedValue: GameRootController.preview(container: modelContext.container))
    }

    @Query(filter: #Predicate<ItemDataModel>{ $0.displayState == 0 }, sort: \ItemDataModel.name, animation: .smooth) private var items: [ItemDataModel]

    @State private var root: GameRootController

    func body(content: Content) -> some View {
        content
            .environment(root)
            .environment(CacheItemListModel())
            .environment(DeviceRotationModel())
            .environment(TabTitleModel())
            .environment(root.adventureRoot)
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
                    await root.adventureRoot.itemControllable.update(items: items.filter { $0.module == .adventure })
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
            container: root.adventureRoot.itemControllable.container,
            root: root.root
        )
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}

extension GameRootController {
    @MainActor public static func preview(container: ModelContainer) -> GameRootController {
        if let root = MockData.previewRoot {
            return root
        }
        let rootManager = RootManager(
            adventureRoot: AdventureRootModel.preview(container: container), audioRoot: AudioRootModel.preview(container: container), characterRoot: CharacterRootModel.preview(container: container), diceRoot: DiceRootModel.preview(container: container), generatorRoot: AdventureRootModel.preview(container: container), mapRoot: MapRootModel.preview(container: container), pdfRoot: PdfRootModel.preview(container: container), photoRoot: PhotoRootModel.preview(container: container), spaceRoot: SpaceRootModel.preview(container: container), tableRoot: TableRootModel.preview(container: container), weatherRoot: WeatherRootModel.preview(container: container)
        )

        let newRoot = GameRootController(root: rootManager, adventureRoot: AdventureRootModel.preview(container: container), audioRoot: AudioRootModel.preview(container: container), characterRoot: CharacterRootModel.preview(container: container), diceRoot: DiceRootModel.preview(container: container), mapRoot: MapRootModel.preview(container: container), pdfRoot: PdfRootModel.preview(container: container), photoRoot: PhotoRootModel.preview(container: container), spaceRoot: SpaceRootModel.preview(container: container), tableRoot: TableRootModel.preview(container: container), weatherRoot: WeatherRootModel.preview(container: container))

        MockData.previewRoot = newRoot
        return newRoot
    }
}
