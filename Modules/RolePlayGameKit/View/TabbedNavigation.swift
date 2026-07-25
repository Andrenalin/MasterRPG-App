// @copyright André Trettin

import AudioRPG
import CoreRPG
import SwiftUI
import AdventureRPG
#if os(iOS)
import UIKit
#endif

struct TabbedNavigation: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.appTheme) private var theme
    @Environment(\.rolePlayStateRestorationEnabled) private var rolePlayStateRestorationEnabled

    private let restoresState: Bool

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
        .phoneTabBottomAccessory(isEnabled: shouldShowPhoneBottomAccessory) {
            PhoneTabBottomAccessory(
                showsAudioPlayer: appModel.audioRoot.audioPlayerModel.showPlayerToolBar
            )
        }
        .environment(
            \.audioPlayerUsesTabAccessory,
            usesPhoneTabAccessory
        )
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
    private var shouldShowPhoneBottomAccessory: Bool {
        usesPhoneTabAccessory &&
        appModel.audioRoot.audioPlayerModel.showPlayerToolBar
    }

    private var usesPhoneTabAccessory: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
#endif
}

#if os(iOS)
private struct PhoneTabBottomAccessory: View {
    let showsAudioPlayer: Bool

    var body: some View {
        if showsAudioPlayer {
            AudioPlayerMiniBarView()
        }
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
