// @copyright André Trettin

import CoreRPG
import SwiftUI
import TipKit

struct SplitVisionNavigation: View {
    @Environment(AppModel.self) private var appModel
    @Environment(ScenesManager.self) private var scenesManager

    private let restoresState: Bool
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    init(restoresState: Bool = true) {
        self.restoresState = restoresState
    }
    
    var body: some View {
        @Bindable var appModel = appModel
        
        TabView(selection: $appModel.selectedModule) {
            ForEach(RootRoute.visionTabs) { tab in
                Tab(tab.title, systemImage: tab.icon, value: tab, role: tab == .search ? .search : nil) {
                    SplitTabContentView(tab: tab, appModel: appModel, column: $column, preferredCompactColumn: $preferredCompactColumn)
                }
            }
        }
        .applyIf(restoresState) {
            $0.modifier(SplitVisionNavigationRestorationModifier(appModel: appModel))
        }
        .focusedSceneValue(\.selectedModule, $appModel.menuSelectedModule)
        .onNavigationReceive { (route: RootRoute, navigator) in
            guard RootRoute.visionTabs.contains(route) else {
                return .immediately
            }
            if appModel.selectedModule == route {
                return .immediately
            }
            appModel.selectedModule = route
            return .after(NavigationTiming.tabSwitchMountDelay)
        }
#if os(visionOS)
        .ornament(attachmentAnchor: .scene(.trailing), contentAlignment: .leading) {
            VStack {
                ModuleWindowMenuView()
            }
            .padding(12)
            .environment(scenesManager)
        }
        .ornament(attachmentAnchor: .scene(.bottomLeading), contentAlignment: .topLeading) {
            VStack(alignment: .leading, spacing: 8) {
                // `.popoverTip` presents via `UIPopoverPresentationController`, which needs
                // the anchor view attached to a window's regular view hierarchy. Ornament
                // content is composited as a separate scene attachment, so the popover can't
                // resolve a `sourceView`, crashing on first presentation. An inline `TipView`
                // avoids the popover presentation path entirely.
                TipView(MasterRPGTips.openAnotherWindow, arrowEdge: .bottom)

                Button {
                    openEditorWindow()
                } label: {
                    Label {
                        Text("Editor", bundle: .module)
                    } icon: {
                        Image(systemName: NetworkModules.editor.icon)
                    }
                }
            }
            .padding([.top, .leading], 12)
            .environment(scenesManager)
        }
#endif
    }
    
    var selectedModule: NetworkModules {
        (appModel.selectedExtendedModule?.module ?? appModel.selectedModule?.module) ?? .game
    }

    private func openEditorWindow() {
        scenesManager.openWindow(.editor)
        MasterRPGTips.recordWindowOpened()
    }
}

#Preview {
    let appModel = AppModel.previewWithoutDatabase

    SplitVisionNavigation(restoresState: false)
        .environment(appModel)
        .environment(appModel.scenesManager)
}

private struct SplitVisionNavigationRestorationModifier: ViewModifier {
    @SceneStorage("GameRoute") private var storedTab: RootRoute = .game

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
