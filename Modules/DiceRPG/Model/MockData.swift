// @copyright André Trettin

import CoreRPG
import SwiftUI
import SwiftData

struct MockData: PreviewModifier {
    nonisolated static let previewId = DiceModel.previewId

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
    @State private var root: DiceRootModel
    @State private var diceDisplayModel: DiceDisplayModel
    @State private var appGameStateModel: AppGameStateModel
    @State private var appNavigationModel: AppNavigationModel

    init(
        root: DiceRootModel = .previewFixture(),
        diceDisplayModel: DiceDisplayModel = DiceDisplayModel()
    ) {
        let appGameStateModel = AppGameStateModel()
        self._root = State(wrappedValue: root)
        self._diceDisplayModel = State(wrappedValue: diceDisplayModel)
        self._appGameStateModel = State(wrappedValue: appGameStateModel)
        self._appNavigationModel = State(
            wrappedValue: AppNavigationModel(appGameStateModel: appGameStateModel)
        )
    }

    func body(content: Content) -> some View {
        content
            .environment(root)
            .environment(diceDisplayModel)
            .environment(appGameStateModel)
            .environment(appNavigationModel)
            .environment(AppWindowSizeModel())
            .environment(CacheItemListModel())
            .environment(ScenesManager())
#if os(macOS)
            .frame(width: 800, height: 600)
#endif
            .moduleTint(root.configurable.module)
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}
