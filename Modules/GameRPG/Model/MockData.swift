// @copyright André Trettin

import CoreRPG
import RPGResources
import SwiftUI
import SwiftData
import AdventureRPG

struct MockData: PreviewModifier {
    nonisolated static let previewId = UUID()
    nonisolated static let previewId2 = UUID()
    nonisolated static let previewId3 = UUID()
    
    //static var previewRoot: AdventureRootModel?

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
            print("url nil")
            return container
        }

        let root = GameRoot.preview
        let task = root.adventureRoot.importControllable.importUrl(from: url)
        let _ = try await task.value

        return container
    }
}

struct MockRootViewModifier: ViewModifier {
    init(modelContext: ModelContext) {
        self._root = State(wrappedValue: GameRoot.preview)
    }

    @State private var root: GameRoot
    @State private var appGameStateModel: AppGameStateModel = AppGameStateModel()

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
            .environment(appGameStateModel)
            .environment(AppSettingsModel())
            .environment(AppNavigationModel(appGameStateModel: appGameStateModel))
            .environment(ScenesManager())
            .setAppSizeMode()
#if os(macOS)
            .frame(width: 800, height: 600)
#endif
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}
