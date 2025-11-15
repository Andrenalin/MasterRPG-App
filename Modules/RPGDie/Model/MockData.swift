// @copyright André Trettin

import AndrenalinKit
import RPGResources
import SwiftUI
import SwiftData

struct MockData: PreviewModifier {
    static let previewId = UUID()
    static let previewId2 = UUID()
    static let previewId3 = UUID()
    
    static var previewRoot: DiceRootModel?

    func body(content: Content, context: ModelContainer) -> some View {
        content
            .modifier(MockRootViewModifier(modelContext: context.mainContext))
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

        let root = DiceRootModel.preview
        let task = root.importController.importUrl(from: url)
        let _ = try await task.value

        return container
    }
}

struct MockRootViewModifier: ViewModifier {
    init(modelContext: ModelContext) {
        self._root = State(wrappedValue: DiceRootModel.preview)
    }

    @State private var root: DiceRootModel

    func body(content: Content) -> some View {
        content
            .environment(root)
            .environment(root.searchModel)
            .environment(root.listDisplayModel)
            .environment(root.rootController)
            .environment(ListModel.preview)
            .environment(CacheItemListModel())
            .environment(DeviceRotationModel())
            .environment(SelectionSheetLinkModel())
            .environment(ExternalHeaderModel())
#if os(macOS)
            .frame(width: 800, height: 600)
#endif
            .tint(root.module.tint)
            .accentColor(root.module.tint)
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}
