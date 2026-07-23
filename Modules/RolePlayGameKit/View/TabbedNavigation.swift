// @copyright André Trettin

import AudioRPG
import CoreRPG
import SwiftUI
import AdventureRPG
#if !os(tvOS)
import GeneratorRPG
#endif

struct TabbedNavigation: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.rolePlayStateRestorationEnabled) private var rolePlayStateRestorationEnabled
    @Environment(AppWindowSizeModel.self) private var appSizeModel

    private let restoresState: Bool

#if os(iOS)
    @State private var aiAssistantContexts: [SheetAIAssistantContext] = []
#endif

    init(restoresState: Bool = true) {
        self.restoresState = restoresState
    }

    var body: some View {
        @Bindable var appModel = appModel
        
        TabView(selection: $appModel.selectedModule) {
            ForEach(RootRoute.fiveTabs) { tab in
                Tab(value: tab, role: tab.tabRole) {
                    ManagedNavigationStack(name: tab.title) { navigator in
                        tab
                    }
                    .tint(color(for: tab))
                    .environment(itemRootController(for: tab))
                } label: {
                    ModuleTabLabel(route: tab, color: color(for: tab))
                }
            }
        }
#if os(iOS)
        .onPreferenceChange(SheetAIAssistantContextPreferenceKey.self) { newContexts in
            if aiAssistantContexts != newContexts {
                aiAssistantContexts = newContexts
            }
        }
        .tabViewBottomAccessory {
            if appSizeModel.mode == .compact,
               appModel.audioRoot.audioPlayerModel.showPlayerToolBar || aiAssistantContext != nil {
                PhoneTabBottomAccessory(
                    showsAudioPlayer: appModel.audioRoot.audioPlayerModel.showPlayerToolBar,
                    aiAssistantContext: aiAssistantContext
                )
            }
        }
        .tabBarMinimizeBehavior26(
            aiAssistantContext?.rootModel.isAIModeActive == true ? .never : .onScrollDown
        )
#endif
        .applyIf(restoresState && rolePlayStateRestorationEnabled) {
            $0.modifier(TabbedNavigationRestorationModifier(appModel: appModel))
        }
        .focusedSceneValue(\.selectedModule, $appModel.menuSelectedModule)
        .onNavigationReceive { (route: RootRoute, navigator) in
            guard RootRoute.fiveTabs.contains(route) else {
                guard appModel.selectedModule != .editors else { return .immediately }
                appModel.selectedModule = .editors
                return .after(0.8)
            }
            if appModel.selectedModule == route {
                return .immediately
            }
            appModel.selectedModule = route
            return .after(0.8)
        }
    }
    
    func color(for tab: RootRoute) -> Color {
        (tab == .editors ? selectedModule : tab.module).tint
    }
    
    func itemRootController(for tab: RootRoute) -> ItemRootController {
        appModel.itemRootController(for: tab == .editors ? selectedModule : tab.module) ?? appModel.adventureRoot.rootController
    }
    
    var selectedModule: NetworkModules {
        guard let appModule = appModel.selectedModule?.module else { return .game }
        return appModule == .editor ? (appModel.selectedExtendedModule?.module ?? .game) : appModule
    }

#if os(iOS)
    private var aiAssistantContext: SheetAIAssistantContext? {
        aiAssistantContexts.last { $0.module == selectedModule }
    }
#endif
}

#if os(iOS)
private struct PhoneTabBottomAccessory: View {
    let showsAudioPlayer: Bool
    let aiAssistantContext: SheetAIAssistantContext?

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        if let aiAssistantContext, aiAssistantContext.rootModel.isAIModeActive {
            aiAssistantView(aiAssistantContext)
        } else if placement == .inline {
            HStack(spacing: 0) {
                if showsAudioPlayer {
                    AudioPlayerMiniBarView()
                }
                if let aiAssistantContext {
                    aiAssistantView(aiAssistantContext)
                }
            }
        } else {
            VStack(spacing: 0) {
                if showsAudioPlayer {
                    AudioPlayerMiniBarView()
                }
                if let aiAssistantContext {
                    aiAssistantView(aiAssistantContext)
                }
            }
        }
    }

    private func aiAssistantView(_ context: SheetAIAssistantContext) -> some View {
        SheetAIAssistantOverlayView(
            module: context.module,
            itemId: context.itemId,
            rootModel: context.rootModel
        )
    }
}
#endif

#Preview {
    TabbedNavigation(restoresState: false)
        .environment(AppModel.previewWithoutDatabase)
        .environment(AppWindowSizeModel())
}

private struct TabbedNavigationRestorationModifier: ViewModifier {
    @SceneStorage("RootRoute") private var storedTab: RootRoute = .game

    let appModel: AppModel

    func body(content: Content) -> some View {
        @Bindable var appModel = appModel

        content
            .syncOptionalState(
                source: $storedTab,
                destination: $appModel.selectedModule
            ) { newValue in
                if appModel.menuSelectedModule != newValue.module {
                    appModel.menuSelectedModule = newValue.module
                }
            }
    }
}

extension RootRoute {
    var tabRole: TabRole? {
        self == .search ? .search : nil
    }
}
