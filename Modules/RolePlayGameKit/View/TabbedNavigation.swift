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

    private let restoresState: Bool

    init(restoresState: Bool = true) {
        self.restoresState = restoresState
    }

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
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
        .phoneTabBottomAccessory(isEnabled: shouldShowPhoneBottomAccessory) {
            AudioPlayerMiniBarView()
        }
        .tabBarMinimizeBehavior(.onScrollDown)
#endif
        .applyIf(restoresState) {
            $0.modifier(TabbedNavigationRestorationModifier(appModel: appModel))
        }
        .focusedSceneValue(\.selectedModule, $appModel.menuSelectedModule)
        .onNavigationReceive { (route: RootRoute, navigator) in
            guard RootRoute.fiveTabs.contains(route) else {
                guard appModel.selectedModule != .editors else { return .immediately }
                appModel.selectedModule = .editors
                return .after(NavigationTiming.tabSwitchMountDelay)
            }
            if appModel.selectedModule == route {
                return .immediately
            }
            appModel.selectedModule = route
            return .after(NavigationTiming.tabSwitchMountDelay)
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

    private var shouldShowPhoneBottomAccessory: Bool {
        appModel.audioRoot.audioPlayerModel.showPlayerToolBar
    }
}

#if os(iOS)
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
            content.applyIf(isEnabled) {
                $0.tabViewBottomAccessory {
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
        .environment(ScenesManager())
        .environment(AppGameStateModel())
        .environmentSetUp(AppModel.previewWithoutDatabase)
}

private struct TabbedNavigationRestorationModifier: ViewModifier {
    @SceneStorage(RootRoute.sceneStorageKey) private var storedTab: RootRoute = RootRoute.defaultRoute

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
