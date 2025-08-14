// @copyright André Trettin

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
            for: AudioDataModel.self, TagDataModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        
        guard try! container.mainContext.fetch(FetchDescriptor<AudioDataModel>()).isEmpty else {
            return container
        }
        let model1 = AudioDataModel(
            id: previewId,
            name: "Mega Nice Photo",
            information: "A lot of information about this photo",
            category: .adventure,
            tags: ["Example", "Title", "Ouside"]
        )
        container.mainContext.insert(model1)
        
        let model2 = AudioDataModel(
            id: previewId2,
            name: "Albert",
            information: "The is an example photo and the information is also set here",
            category: .character,
            tags: ["Player", "Mega", "Gnome"]
        )
        container.mainContext.insert(model2)
        
        let model3 = AudioDataModel(
            id: previewId3,
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
        self._root = State(wrappedValue: AudioRootModel(modelContext: modelContext))
    }
    
    @State private var root: AudioRootModel
    
    func body(content: Content) -> some View {
        content.environment(root)
            .environment(root.searchModel)
            .environment(root.listModel)
            .environment(root.listDisplayModel)
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
