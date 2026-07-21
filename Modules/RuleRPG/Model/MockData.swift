// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct MockData: PreviewModifier {
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

private struct MockRootViewModifier: ViewModifier {
    @State private var root = RuleRootModel.preview
    @State private var appGameStateModel = AppGameStateModel()
    @State private var appNavigationModel: AppNavigationModel

    init() {
        let gameState = AppGameStateModel()
        _appGameStateModel = State(initialValue: gameState)
        _appNavigationModel = State(
            initialValue: AppNavigationModel(appGameStateModel: gameState)
        )
    }

    func body(content: Content) -> some View {
        content
            .environment(root)
            .environment(appGameStateModel)
            .environment(appNavigationModel)
            .environment(AppWindowSizeModel())
            .environment(CacheItemListModel())
            .environment(ScenesManager())
            .tint(NetworkModules.rule.tint)
#if os(macOS)
            .frame(width: 800, height: 600)
#endif
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}
