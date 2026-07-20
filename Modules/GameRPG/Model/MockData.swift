// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftData
import SwiftUI

struct MockData: PreviewModifier {
    func body(content: Content, context: ModelContainer) -> some View {
        content
            .modifier(MockRootViewModifier(root: .previewFixture()))
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
    @State private var root: GameRoot
    @State private var appGameStateModel: AppGameStateModel
    @State private var appNavigationModel: AppNavigationModel
    @State private var diceDisplayModel = DiceDisplayModel()
    @State private var appWindowSizeModel = AppWindowSizeModel()
    @State private var cacheItemListModel = CacheItemListModel()
    @State private var appSettingsModel = AppSettingsModel()
    @State private var scenesManager = ScenesManager()

    init(root: GameRoot) {
        let appGameStateModel = AppGameStateModel()
        _root = State(initialValue: root)
        _appGameStateModel = State(initialValue: appGameStateModel)
        _appNavigationModel = State(
            initialValue: AppNavigationModel(appGameStateModel: appGameStateModel)
        )
    }

    func body(content: Content) -> some View {
        content
            .environment(root.adventureRoot)
            .environment(root.audioRoot)
            .environment(root.characterRoot)
            .environment(root.diceRoot)
            .environment(root.mapRoot)
            .environment(root.pdfRoot)
            .environment(root.photoRoot)
            .environment(root.spaceRoot)
            .environment(root.tableRoot)
            .environment(root.weatherRoot)
            .environment(diceDisplayModel)
            .environment(appGameStateModel)
            .environment(appWindowSizeModel)
            .environment(cacheItemListModel)
            .environment(appSettingsModel)
            .environment(appNavigationModel)
            .environment(scenesManager)
            .setAppSizeMode()
#if os(macOS)
            .frame(width: 800, height: 600)
#endif
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self { .modifier(MockData()) }
}
