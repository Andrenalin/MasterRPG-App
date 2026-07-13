// @copyright André Trettin

import AudioRPG
import CoreRPG
import SwiftUI
import AdventureRPG

#Preview {
    ModuleTabLabel(route: .game)
        .padding()
}

struct TabbedNavigation: View {
    @SceneStorage("RootRoute") private var storedTab: RootRoute = .game

    @Environment(AppModel.self) private var appModel
    @Environment(AppWindowSizeModel.self) private var appSizeModel
        
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
        .tabBarMinimizeBehavior26(.onScrollDown)
        .applyIf(appModel.audioRoot.audioPlayerModel.showPlayerToolBar) {
            $0.tabViewBottomAccessory {
                if appSizeModel.mode == .compact && appModel.audioRoot.audioPlayerModel.showPlayerToolBar {
                    AudioPlayerMiniBarView()
                }
            }
        }
#endif
        .syncOptionalState(
            source: $storedTab,
            destination: $appModel.selectedModule
        ) { newValue in
            if appModel.menuSelectedModule != newValue.module {
                appModel.menuSelectedModule = newValue.module
            }
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
}

#Preview {
    TabbedNavigation()
}

struct ModuleTabLabel: View {
    let title: String
    let icon: String
    let color: Color

    init(route: RootRoute, color: Color? = nil) {
        title = route.title
        icon = route.icon
        self.color = color ?? route.module.tint
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
        }
    }
}

extension RootRoute {
    var tabRole: TabRole? {
        self == .search ? .search : nil
    }
}
