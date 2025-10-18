// @copyright André Trettin

#if !os(tvOS)
import AndrenalinKit
import RoleGameKit
import SwiftUI

import RPGPdfs
import RPGSpaces


struct WindowViewerList: Scene {
    let appStore: AppStore
    
    var body: some Scene {
        Group {
//            windowGroup(model: appStore, module: .generator) { selection in
//                appStore.generatorRoot.viewController.windowViewer(root: appStore.generatorRoot, selection: selection)
//            }

//            windowGroup(model: appStore, module: .pdf) { selection in
//                appStore.pdfRoot.viewController.windowViewer(root: appStore.pdfRoot, selection: selection)
//            }

            windowGroup(model: appStore, module: .space) { selection in
                appStore.spaceRoot.viewController.windowViewer(root: appStore.spaceRoot, selection: selection)
            }
            

//            windowGroup(model: appStore, module: .table) { selection in
//                appStore.tableRoot.viewController.windowViewer(root: appStore.tableRoot, selection: selection)
//            }
//
//            windowGroup(model: appStore, module: .weather) { selection in
//                appStore.weatherRoot.viewController.windowViewer(root: appStore.weatherRoot, selection: selection)
//            }
        }
        .defaultSize(CGSize(width: 600, height: 800))
    }
    
    private func windowGroup<Content: View>(model: AppStore, module: NetworkModules, content: @escaping (WindowItemSelection) -> Content) -> some Scene {
        WindowGroup("\(module.title) Viewer", id: module.viewerWindowId, for: WindowItemSelection.self) { $selection in
            DataBaseAppStoreAvailable(appStore: appStore) { _ in
                content(selection ?? WindowItemSelection(itemId: UUID()))
                    .modifier(WindowViewerSetUpViewModifier(model: model, module: module))
            }
        }
        .windowResizability(.contentSize)
        .defaultWindowPlacementAll(model.windowPlacement(for: module))
#if !os(iOS)
        .restorationBehavior(.disabled)
#endif
    }
}

struct WindowViewerSetUpViewModifier: ViewModifier {
    let model: AppStore
    let module: NetworkModules
    
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .resetAppColorScheme()
            .frame(minWidth: 600, minHeight: 400)
            .handlesExternalEvents(preferring: [], allowing: [])
            .tint(module.tint)
            .environmentSetUp(model)
#if os(iOS)
            .environment(\.colorScheme, model.settingsModel.appColorScheme.colorScheme(for: colorScheme))
#endif
#if os(macOS)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
#endif
    }
}

#endif
