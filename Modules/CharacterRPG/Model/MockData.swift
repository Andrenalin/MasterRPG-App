// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import SwiftUI
import SwiftData

struct MockData: PreviewModifier {
    nonisolated static let previewId = ValueModel.previewId

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
    @State private var root: CharacterRootModel
#if !os(tvOS)
    @State private var generatorRoot: GeneratorRootModel
#endif
    @State private var appGameStateModel: AppGameStateModel
    @State private var appNavigationModel: AppNavigationModel

    init() {
        let appGameStateModel = AppGameStateModel()
        self._root = State(wrappedValue: CharacterRootModel.previewFixture())
#if !os(tvOS)
        self._generatorRoot = State(wrappedValue: GeneratorRootModel.previewFixture())
#endif
        self._appGameStateModel = State(wrappedValue: appGameStateModel)
        self._appNavigationModel = State(
            wrappedValue: AppNavigationModel(appGameStateModel: appGameStateModel)
        )
    }

    func body(content: Content) -> some View {
        content
            .environment(root)
#if !os(tvOS)
            .environment(generatorRoot)
#endif
            .environment(appGameStateModel)
            .environment(SearchBarVisibleModel())
            .environment(appNavigationModel)
            .environment(AppWindowSizeModel())
            .environment(CacheItemListModel())
            .environment(ScenesManager())
            .environment(root.diceRoot)
            .environment(root.tableRoot)
            .environment(root.photoRoot)
            .environment(root.pdfRoot)
#if os(macOS)
            .frame(width: 800, height: 600)
#endif
            .moduleTint(root.configurable.module)
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}
