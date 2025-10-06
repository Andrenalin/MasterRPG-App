// @copyright André Trettin

import CoreRPG
import RPGResources
import SwiftUI
import SwiftData

struct MockData: PreviewModifier {
    static let previewId = UUID()
    static let previewId2 = UUID()
    static let previewId3 = UUID()
    
    static var previewRoot: PdfRootModel?
    
    func body(content: Content, context: ModelContainer) -> some View {
        content
            .modifier(MockRootViewModifier(modelContext: context.mainContext))
            .modelContainer(context)
    }
    static func makeSharedContext() async throws -> ModelContainer {
        let container = try! ModelContainer(
            for: ItemDataModel.self, TagDataModel.self, PdfEntryDataModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        
        guard try! container.mainContext.fetch(FetchDescriptor<ItemDataModel>()).isEmpty else {
            return container
        }
        
        let bundle = Resources.bundle
        guard let url = bundle.url(forResource: Resources.exampleFirstData, withExtension: "gmz") else {
            print("url nil ")
            return container
        }

        let root = PdfRootModel(modelContext: container.mainContext)
        let task = root.importController.importUrl(from: url)
        let _ = try await task.value

        let model1 = ItemDataModel(
            id: previewId,
            module: .pdf,
            name: "Mega Nice Photo",
            information: "A lot of information about this photo",
            category: .adventure,
            tags: ["Example", "Title", "Ouside"]
        )
        container.mainContext.insert(model1)
        
        let model2 = ItemDataModel(
            id: previewId2,
            module: .pdf,
            name: "Albert",
            information: "The is an example photo and the information is also set here",
            category: .character,
            tags: ["Player", "Mega", "Gnome"]
        )
        container.mainContext.insert(model2)
        
        let model3 = ItemDataModel(
            id: previewId3,
            module: .pdf,
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
        self._root = State(wrappedValue: PdfRootModel(modelContext: modelContext))
    }
    
    @Query(filter: #Predicate<ItemDataModel>{ $0.displayState == 0 }, sort: \ItemDataModel.name, animation: .smooth) private var items: [ItemDataModel]
    
    @State private var root: PdfRootModel
    
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
            .environment(LinkRootController(container: root.itemController.container, root: RootManager.preview(fake: root)))
#if os(macOS)
            .frame(width: 800, height: 600)
#endif
            .onChange(of: items, initial: true) {
                Task {
                    await root.itemController.update(items: items.filter { $0.module == .pdf })
                }
            }
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}

extension PdfRootModel {
    @MainActor public static func preview(container: ModelContainer) -> PdfRootModel {
        if let root = MockData.previewRoot {
            return root
        }
        let newRoot = PdfRootModel(modelContext: container.mainContext)
        MockData.previewRoot = newRoot
        return newRoot
    }
}
