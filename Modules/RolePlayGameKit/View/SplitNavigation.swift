// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import SwiftUI
import TipKit

struct SplitNavigation: View {
    @Environment(AppModel.self) private var appModel
    @Environment(ScenesManager.self) private var scenesManager

    private let restoresState: Bool
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .content

    init(restoresState: Bool = true) {
        self.restoresState = restoresState
    }
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        @Bindable var appModel = appModel

        SplitNavigationAllTabsView(column: $column, preferredCompactColumn: $preferredCompactColumn)
            .applyIf(restoresState) {
                $0.modifier(SplitNavigationRestorationModifier(appModel: appModel))
            }
            .focusedSceneValue(\.selectedModule, $appModel.menuSelectedModule)
            .onNavigationReceive(assign: $appModel.selectedModule, delay: NavigationTiming.tabSwitchMountDelay)
#if os(macOS)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        scenesManager.openWindow(.editor)
                        MasterRPGTips.recordWindowOpened()
                    } label: {
                        Label {
                            Text("Open Editor Window", bundle: .module)
                        } icon: {
                            Image(systemName: NetworkModules.editor.icon)
                        }
                    }
                    .popoverTip(MasterRPGTips.openAnotherWindow)
                }
            }
#endif
    }
    
    var selectedModule: NetworkModules {
        (appModel.selectedModule ?? RootRoute.defaultRoute).module
    }
}

#Preview {
    let appModel = AppModel.previewWithoutDatabase

    SplitNavigation(restoresState: false)
        .environment(appModel)
        .environment(appModel.appNavigationModel)
        .environment(AppWindowSizeModel())
}

private struct SplitNavigationRestorationModifier: ViewModifier {
    @AppStorage("MasterRPGCustomization") private var customization: TabViewCustomization
    @SceneStorage(RootRoute.sceneStorageKey) private var storedTab: RootRoute = RootRoute.defaultRoute

    let appModel: AppModel

    func body(content: Content) -> some View {
        @Bindable var appModel = appModel

        content
            .tabViewCustomization($customization)
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

private struct SplitNavigationAllTabsView: View {
    @Environment(AppModel.self) private var appModel

    @Binding var column: NavigationSplitViewVisibility
    @Binding var preferredCompactColumn: NavigationSplitViewColumn

    var body: some View {
        @Bindable var appModel = appModel

        TabView(selection: $appModel.selectedModule) {
            pageTab(for: .game)
                .customizationID("Tab.\(NetworkModules.game.token)")
#if !os(macOS)
                .customizationBehavior(.disabled, for: .sidebar, .tabBar)
#endif

            TabSection {
                pageTab(for: .search)
                    .customizationID("Tab.\(NetworkModules.search.token)")
            } header: {
                Text("Special", bundle: .module)
            }
            .customizationID("Tab.Special")
            .defaultVisibility(.hidden, for: .tabBar)

            TabSection {
                pageTab(for: .adventures)
                    .customizationID("Tab.\(NetworkModules.adventure.token)")
                pageTab(for: .values)
                    .customizationID("Tab.\(NetworkModules.value.token)")
                pageTab(for: .maps)
                    .customizationID("Tab.\(NetworkModules.map.token)")
                pageTab(for: .weathers)
                    .customizationID("Tab.\(NetworkModules.weather.token)")
            } header: {
                Text("Library", bundle: .module)
            }
            .customizationID("Tab.Libaray")
            .defaultVisibility(.hidden, for: .tabBar)


            TabSection {
                pageTab(for: .rules)
                    .customizationID("Tab.\(NetworkModules.rule.token)")
                pageTab(for: .pdfs)
                    .customizationID("Tab.\(NetworkModules.pdf.token)")
                pageTab(for: .tables)
                    .customizationID("Tab.\(NetworkModules.table.token)")
            } header: {
                Text("References", bundle: .module)
            }
            .customizationID("Tab.References")
            .defaultVisibility(.hidden, for: .tabBar)

            TabSection {
                pageTab(for: .audios)
                    .customizationID("Tab.\(NetworkModules.audio.token)")
                pageTab(for: .dice)
                    .customizationID("Tab.\(NetworkModules.dice.token)")
                pageTab(for: .photos)
                    .customizationID("Tab.\(NetworkModules.photo.token)")
                pageTab(for: .space)
                    .customizationID("Tab.\(NetworkModules.space.token)")
            } header: {
                Text("Material", bundle: .module)
            }
            .customizationID("Tab.Material")
            .defaultVisibility(.hidden, for: .tabBar)

            TabSection {
                pageTab(for: .settings)
                    .customizationID("Tab.\(NetworkModules.setting.token)")
            } header: {
                Text("Setting", bundle: .module)
            }
            .customizationID("Tab.Util")

        }
        .tabViewStyle(.sidebarAdaptable)
        .defaultTabBarPlacementAll(.sidebar)
    }

    private func pageTab(for tab: RootRoute) -> some TabContent<RootRoute?> {
        Tab(value: tab, role: tab.tabRole) {
            tabView(tab: tab)
                .moduleTint(tab.module)
                .environment(appModel.itemRootController(for: tab.module))
        } label: {
            ModuleTabLabel(route: tab)
        }
    }

    @ViewBuilder private func tabView(tab: RootRoute) -> some View {
        if tab.hasDetailView {
            splitWithDetail(tab: tab)
        } else {
            contentView(tab: tab)
        }
    }

    @ViewBuilder private func contentView(tab: RootRoute) -> some View {
        ManagedPresentationView(name: tab.title) {
            tab
        }
    }

    private func splitWithDetail(tab: RootRoute) -> some View {
        SplitWithDetailView(
            tab: tab,
            column: $column,
            preferredCompactColumn: $preferredCompactColumn,
            appModel: appModel
        )
    }
}

#endif
