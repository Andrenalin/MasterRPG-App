// @copyright André Trettin

import CoreRPG
import SwiftUI
import TipKit

struct SplitEditorNavigation: View {
    @SceneStorage(RootRoute.editorSceneStorageKey) private var storedTab: RootRoute = .pdfs
    
    @Environment(AppModel.self) private var appModel
    @Environment(ScenesManager.self) private var scenesManager
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        @Bindable var appModel = appModel
        
        TabView(selection: $appModel.selectedEditorModule) {
            ForEach(RootRoute.visionEditorTabs) { tab in
                Tab(tab.title, systemImage: tab.icon, value: tab, role: tab == .search ? .search : nil) {
                    SplitTabContentView(tab: tab, appModel: appModel, column: $column, preferredCompactColumn: $preferredCompactColumn)
                }
            }
        }
        .syncOptionalState(
            source: $storedTab,
            destination: $appModel.selectedEditorModule
        ) { newValue in
            if appModel.menuSelectedModule != newValue.module {
                appModel.menuSelectedModule = newValue.module
            }
        }
        .focusedSceneValue(\.selectedModule, $appModel.menuSelectedModule)
        .onNavigationReceive { (route: RootRoute, navigator) in
            guard RootRoute.visionEditorTabs.contains(route) else {
                return .immediately
            }
            if appModel.selectedEditorModule == route {
                return .immediately
            }
            appModel.selectedEditorModule = route
            return .after(NavigationTiming.tabSwitchMountDelay)
        }
#if os(macOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openGameWindow()
                } label: {
                    Label {
                        Text("Open Game Window", bundle: .module)
                    } icon: {
                        Image(systemName: NetworkModules.game.icon)
                    }
                }
                .popoverTip(MasterRPGTips.openAnotherWindow)
            }
        }
#endif
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
                    openGameWindow()
                } label: {
                    Label {
                        Text("Game", bundle: .module)
                    } icon: {
                        Image(systemName: NetworkModules.game.icon)
                    }
                }
            }
            .padding([.top, .leading], 12)
            .environment(scenesManager)
        }
#endif
    }
    
    private func openGameWindow() {
        scenesManager.openWindow(.game)
        MasterRPGTips.recordWindowOpened()
    }
}

#Preview {
    let appModel = AppModel()

    SplitEditorNavigation()
        .environment(appModel)
        .environment(appModel.scenesManager)
}
