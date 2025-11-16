// @copyright André Trettin

import RPGAdventures
import RPGAudios
import RPGValues
import RPGDie
import RPGMaps
import RPGPdfs
import RPGPhotos
import RPGSpaces
import RPGTables
import RPGWeathers

import AndrenalinKit
import RPGResources
import SwiftUI
import SwiftData

struct MockData: PreviewModifier {
    static let previewId = UUID()
    static let previewId2 = UUID()
    static let previewId3 = UUID()
    
    static var previewRoot: GeneratorRootModel?

    func body(content: Content, context: ModelContainer) -> some View {
        content
//            .modifier(MockRootViewModifier(modelContext: context.mainContext))
            .modelContainer(context)
    }
    static func makeSharedContext() async throws -> ModelContainer {
        let container = try! ModelContainer(
            for: TagDataModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        
        let bundle = Resources.bundle
        guard let url = bundle.url(forResource: Resources.exampleFirstData, withExtension: "gmz") else {
            print("url nil ")
            return container
        }

//        let root = GeneratorRootModel.preview
//        let task = root.importController.importUrl(from: url)
//        let _ = try await task.value

        return container
    }
}

//struct MockRootViewModifier: ViewModifier {
//    init(modelContext: ModelContext) {
//        let audioRoot = AudioRootFactory.rootModel(modelContext: modelContext)
//        let diceRoot = DiceRootFactory.rootModel(modelContext: modelContext)
//        let pdfRoot = PdfRootFactory.rootModel(modelContext: modelContext)
//        let photoRoot = PhotoRootFactory.rootModel(modelContext: modelContext)
//        let spaceRoot = SpaceRootFactory.rootModel(modelContext: modelContext)
//        let tableRoot = TableRootFactory.rootModel(modelContext: modelContext, diceRoot: diceRoot, pdfRoot: pdfRoot)
//        let weatherRoot = WeatherRootFactory.rootModel(modelContext: modelContext, photoRoot: photoRoot)
//        let characterRoot = CharacterRootFactory.rootModel(modelContext: modelContext, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
//        let mapRoot = MapRootFactory.rootModel(modelContext: modelContext, characterRoot: characterRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot)
//        let adventureRoot = AdventureRootFactory.rootModel(modelContext: modelContext, audioRoot: audioRoot, characterRoot: characterRoot, diceRoot: diceRoot, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, weatherRoot: weatherRoot)
//        self._root = State(
//            wrappedValue: GeneratorRootModel(
//                modelContext: modelContext,
//                adventureRoot: adventureRoot,
//                audioRoot: audioRoot,
//                characterRoot: characterRoot,
//                diceRoot: diceRoot,
//                mapRoot: mapRoot,
//                pdfRoot: pdfRoot,
//                photoRoot: photoRoot,
//                spaceRoot: spaceRoot,
//                tableRoot: tableRoot,
//                weatherRoot: weatherRoot
//            )
//        )
//    }
//    
//    @State private var root: GeneratorRootModel
//    
//    func body(content: Content) -> some View {
//        content.environment(root)
//            .environment(root.searchModel)
//            .environment(root.listController.listModel)
//            .environment(root.listDisplayModel)
//            .environment(root.rootController)
//            .environment(CacheItemListModel())
//            .environment(DeviceRotationModel())
//            .environment(TabTitleModel())
//            .environment(LinkRootController(container: root.itemController.container, root: RootManager(adventureRoot: root.adventureRoot, audioRoot: root.audioRoot, characterRoot: root.characterRoot, diceRoot: root.diceRoot, generatorRoot: root, mapRoot: root.mapRoot, pdfRoot: root.pdfRoot, photoRoot: root.photoRoot, spaceRoot: root.spaceRoot, tableRoot: root.tableRoot, weatherRoot: root.weatherRoot)))
//#if os(macOS)
//            .frame(width: 800, height: 600)
//#endif
//    }
//}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}
