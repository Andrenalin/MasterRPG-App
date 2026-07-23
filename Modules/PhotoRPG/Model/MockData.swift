// @copyright André Trettin

import CoreRPG
import SwiftUI
import SwiftData

struct MockData: PreviewModifier {
    nonisolated static let previewId = UUID(uuid: (0xA3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))

    func body(content: Content, context: ModelContainer) -> some View {
        content
            .modifier(MockRootViewModifier(modelContext: context.mainContext))
            .modelContainer(context)
    }
    static func makeSharedContext() async throws -> ModelContainer {
        try ModelContainer(
            for: LinkDataModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}

struct MockRootViewModifier: ViewModifier {
    init(
        modelContext _: ModelContext,
        root: PhotoRootModel = .previewFixture()
    ) {
        let appGameStateModel = AppGameStateModel()
        self._root = State(wrappedValue: root)
        self._appGameStateModel = State(wrappedValue: appGameStateModel)
        self._appNavigationModel = State(
            wrappedValue: AppNavigationModel(appGameStateModel: appGameStateModel)
        )
    }

    @State private var root: PhotoRootModel
    @State private var appGameStateModel: AppGameStateModel
    @State private var appNavigationModel: AppNavigationModel

    func body(content: Content) -> some View {
        content
            .environment(root)
            .environment(appGameStateModel)
            .environment(appNavigationModel)
            .environment(AppWindowSizeModel())
            .environment(CacheItemListModel())
            .environment(ScenesManager())
#if os(macOS)
            .frame(width: 800, height: 600)
#endif
            .moduleTint(.photo)
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}
