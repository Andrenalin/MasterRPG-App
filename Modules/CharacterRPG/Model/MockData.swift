// @copyright André Trettin

import CoreRPG
import RPGResources
import SwiftUI
import SwiftData

struct MockData: PreviewModifier {
    nonisolated static let previewId = UUID()
    nonisolated static let previewId2 = UUID()
    nonisolated static let previewId3 = UUID()
    
    static var previewRoot: CharacterRootModel?

    func body(content: Content, context: ModelContainer) -> some View {
        content
            .modifier(MockRootViewModifier(modelContext: context.mainContext))
            .modelContainer(context)
    }
    static func makeSharedContext() async throws -> ModelContainer {
        let container = try! ModelContainer(
            for: LinkDataModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        
        let bundle = RPGResources.Resources.bundle
        guard let url = bundle.url(forResource: RPGResources.Resources.exampleFirstData, withExtension: "gmz") else {
            print("url nil ")
            return container
        }

        let root = CharacterRootModel.preview
        let task = root.importController.importUrl(from: url)
        let _ = try await task.value

        return container
    }
}

struct MockRootViewModifier: ViewModifier {
    init(modelContext: ModelContext) {
        self._root = State(wrappedValue: CharacterRootModel.preview)
    }

    @State private var root: CharacterRootModel

    func body(content: Content) -> some View {
        content
            .environment(root)
            .environment(CacheItemListModel())
            .environment(root.diceRoot)
            .environment(root.tableRoot)
            .environment(root.photoRoot)
            .environment(root.pdfRoot)
#if os(macOS)
            .frame(width: 800, height: 600)
#endif
            .tint(root.configurable.module.tint)
            .accentColor(root.configurable.module.tint)
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}
