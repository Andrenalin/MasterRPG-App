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
    @Environment(\.appTheme) private var theme
    @Environment(\.rolePlayStateRestorationEnabled) private var rolePlayStateRestorationEnabled

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
        .phoneTabBottomAccessory(isEnabled: shouldShowPhoneBottomAccessory) {
            PhoneTabBottomAccessory(
                showsAudioPlayer: appModel.audioRoot.audioPlayerModel.showPlayerToolBar,
                aiAssistantContext: aiAssistantContext
            )
        }
        .tabBarMinimizeBehavior26(
            .onScrollDown
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
        theme.tint(for: tab == .editors ? selectedModule : tab.module)
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
        guard SheetAIGenerationController.isAvailable else { return nil }

        if let publishedContext = aiAssistantContexts.last(where: {
            $0.module == selectedModule && $0.rootModel.hasAIAssistantContent
        }) {
            return publishedContext
        }

        guard let rootController = appModel.itemRootController(for: selectedModule),
              let itemId = rootController.navigationModel.selectedItemId,
              let rootModel = rootController.editControllable.editorModel.sheetRootModel,
              rootModel.sheetModel.source.itemId == itemId,
              rootModel.hasAIAssistantContent else {
            return nil
        }

        return SheetAIAssistantContext(
            module: selectedModule,
            itemId: itemId,
            rootModel: rootModel
        )
    }

    private var shouldShowPhoneBottomAccessory: Bool {
        SheetAIGenerationController.usesPhoneTabAccessory &&
        (appModel.audioRoot.audioPlayerModel.showPlayerToolBar || aiAssistantContext != nil)
    }
#endif
}

#if os(iOS)
private struct PhoneTabBottomAccessory: View {
    let showsAudioPlayer: Bool
    let aiAssistantContext: SheetAIAssistantContext?

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        if placement == .inline {
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
            rootModel: context.rootModel,
            presentation: .tabAccessory
        )
    }
}

private extension View {
    func phoneTabBottomAccessory<Accessory: View>(
        isEnabled: Bool,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        modifier(
            PhoneTabBottomAccessoryModifier(
                isEnabled: isEnabled,
                accessory: accessory()
            )
        )
    }
}

private struct PhoneTabBottomAccessoryModifier<Accessory: View>: ViewModifier {
    let isEnabled: Bool
    let accessory: Accessory

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isEnabled) {
                accessory
            }
        } else {
            content.tabViewBottomAccessory {
                if isEnabled {
                    accessory
                }
            }
        }
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
