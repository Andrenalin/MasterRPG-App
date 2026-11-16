// @copyright André Trettin

import CoreRPG
import SwiftUI
import SwiftData

struct MockData: PreviewModifier {
    nonisolated static let previewId = AdventureModel.previewId

    func body(content: Content, context: ModelContainer) -> some View {
        content
            .modifier(MockRootViewModifier())
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
    @State private var root: AdventureRootModel
    @State private var appGameStateModel: AppGameStateModel
    @State private var appNavigationModel: AppNavigationModel

    init() {
        let appGameStateModel = AppGameStateModel()
        self._root = State(wrappedValue: AdventureRootModel.previewFixture())
        self._appGameStateModel = State(wrappedValue: appGameStateModel)
        self._appNavigationModel = State(
            wrappedValue: AppNavigationModel(appGameStateModel: appGameStateModel)
        )
    }

    func body(content: Content) -> some View {
        content
            .environment(root)
            .environment(appGameStateModel)
            .environment(SearchBarVisibleModel())
            .environment(appNavigationModel)
            .environment(AppWindowSizeModel())
            .environment(CacheItemListModel())
            .environment(ScenesManager())
            .environment(root.audioRoot)
            .environment(root.characterRoot)
            .environment(root.diceRoot)
            .environment(root.mapRoot)
            .environment(root.pdfRoot)
            .environment(root.photoRoot)
            .environment(root.spaceRoot)
            .environment(root.tableRoot)
            .environment(root.weatherRoot)
#if os(macOS)
            // A representative Mac window size for previews — not tied to any specific
            // app default, just large enough to show the split view meaningfully.
            .frame(width: 800, height: 600)
#endif
            .moduleTint(root.configurable.module)
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}
