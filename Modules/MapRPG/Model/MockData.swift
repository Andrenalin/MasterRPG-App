// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import SwiftUI
import SwiftData

struct MockData: PreviewModifier {
    nonisolated static let previewId = UUID(uuid: (0xA1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))

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
    init(modelContext: ModelContext) {
        let appGameStateModel = AppGameStateModel()
        self._root = State(wrappedValue: MapRootModel.previewFixture())
        self._dropPinModel = State(wrappedValue: DropPinModel())
#if !os(tvOS)
        self._generatorRoot = State(wrappedValue: GeneratorRootModel.preview)
#endif
        self._appGameStateModel = State(wrappedValue: appGameStateModel)
        self._appNavigationModel = State(
            wrappedValue: AppNavigationModel(appGameStateModel: appGameStateModel)
        )
    }

    @State private var root: MapRootModel
    @State private var dropPinModel: DropPinModel
#if !os(tvOS)
    @State private var generatorRoot: GeneratorRootModel
#endif
    @State private var appGameStateModel: AppGameStateModel
    @State private var appNavigationModel: AppNavigationModel

    func body(content: Content) -> some View {
        content
            .environment(root)
            .environment(dropPinModel)
#if !os(tvOS)
            .environment(generatorRoot)
#endif
            .environment(appGameStateModel)
            .environment(appNavigationModel)
            .environment(AppWindowSizeModel())
            .environment(CacheItemListModel())
            .environment(ScenesManager())
            .environment(root.audioRoot)
            .environment(root.characterRoot)
            .environment(root.diceRoot)
            .environment(root.pdfRoot)
            .environment(root.photoRoot)
            .environment(root.tableRoot)
#if os(macOS)
            .frame(width: 800, height: 600)
#endif
            .moduleTint(root.configurable.module)
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}
