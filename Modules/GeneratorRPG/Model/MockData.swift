// @copyright André Trettin

import AdventureRPG
import AudioRPG
import CharacterRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG

import CoreRPG
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
            for: ItemDataModel.self, TagDataModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        
        let model1 = ItemDataModel(
            id: previewId,
            module: .generator,
            name: "Mega Nice",
            information: "A lot of information about this item",
            category: .adventure,
            tags: ["Example", "Title", "Ouside"]
        )
        container.mainContext.insert(model1)
        
        let model2 = ItemDataModel(
            id: previewId2,
            module: .generator,
            name: "Albert",
            information: "The is an example photo and the information is also set here",
            category: .character,
            tags: ["Player", "Mega", "Gnome"]
        )
        container.mainContext.insert(model2)
        
        let model3 = ItemDataModel(
            id: previewId3,
            module: .generator,
            name: "Zauberer",
            information: "A photo of a wizard.",
            category: .adventure,
            tags: ["NPC", "Wizward", "Schwarzmagier"]
        )
        container.mainContext.insert(model3)
        return container
    }
}

struct MockRootViewModifier: ViewModifier {
    init(modelContext: ModelContext) {
        let audioRoot = AudioRootFactory.rootModel(modelContext: modelContext)
        let diceRoot = DiceRootFactory.rootModel(modelContext: modelContext)
        let pdfRoot = PdfRootFactory.rootModel(modelContext: modelContext)
        let photoRoot = PhotoRootFactory.rootModel(modelContext: modelContext)
        let spaceRoot = SpaceRootFactory.rootModel(modelContext: modelContext)
        let tableRoot = TableRootFactory.rootModel(modelContext: modelContext, diceRoot: diceRoot, pdfRoot: pdfRoot)
        let weatherRoot = WeatherRootFactory.rootModel(modelContext: modelContext, photoRoot: photoRoot)
        let characterRoot = CharacterRootFactory.rootModel(modelContext: modelContext, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
        let mapRoot = MapRootFactory.rootModel(modelContext: modelContext, characterRoot: characterRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
        let adventureRoot = AdventureRootFactory.rootModel(modelContext: modelContext, audioRoot: audioRoot, characterRoot: characterRoot, diceRoot: diceRoot, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, weatherRoot: weatherRoot)
        self._root = State(
            wrappedValue: GeneratorRootModel(
                modelContext: modelContext,
                adventureRoot: adventureRoot,
                audioRoot: audioRoot,
                characterRoot: characterRoot,
                diceRoot: diceRoot,
                mapRoot: mapRoot,
                pdfRoot: pdfRoot,
                photoRoot: photoRoot,
                spaceRoot: spaceRoot,
                tableRoot: tableRoot,
                weatherRoot: weatherRoot
            )
        )
    }
    
    @State private var root: GeneratorRootModel
    
    func body(content: Content) -> some View {
        content.environment(root)
            .environment(root.searchModel)
            .environment(root.listController.listModel)
            .environment(root.listDisplayModel)
            .environment(root.rootController)
            .environment(CacheItemListModel())
            .environment(DeviceRotationModel())
            .environment(TabTitleModel())
#if os(macOS)
            .frame(width: 800, height: 600)
#endif
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}
