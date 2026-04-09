// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import RolePlayGameKit
import SwiftUI

import AdventureRPG
import CharacterRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG

import GeneratorRPG
import GameRPG

struct WindowViewerList: Scene {
    let appModel: AppModel
    
    var body: some Scene {
        Group {
            windowGroup(model: appModel, module: .adventure) { selection in
                appModel.adventureRoot.viewController.viewer(root: appModel.adventureRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: closeButton, addToolbar: true))
            }

            windowGroup(model: appModel, module: .value) { selection in
                appModel.characterRoot.viewController.viewer(root: appModel.characterRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: closeButton, addToolbar: true))
            }
            
            windowGroup(model: appModel, module: .generator) { selection in
                appModel.generatorRoot.viewController.viewer(root: appModel.generatorRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: closeButton, addToolbar: true))
            }

            windowGroup(model: appModel, module: .map) { selection in
                appModel.mapRoot.viewController.viewer(root: appModel.mapRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: closeButton, addToolbar: true))
            }

            windowGroup(model: appModel, module: .pdf) { selection in
                appModel.pdfRoot.viewController.viewer(root: appModel.pdfRoot, itemId: selection.itemId, entryId: selection.entryId, configuration: ViewerConfiguration(closeButton: closeButton, addToolbar: true))
            }

            windowGroup(model: appModel, module: .photo) { selection in
                appModel.photoRoot.viewController.viewer(root: appModel.photoRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: closeButton, addToolbar: true))
            }

            windowGroup(model: appModel, module: .space) { selection in
                appModel.spaceRoot.viewController.viewer(root: appModel.spaceRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: closeButton, addToolbar: true))
            }
            
            windowGroup(model: appModel, module: .table) { selection in
                appModel.tableRoot.viewController.viewer(root: appModel.tableRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: closeButton, addToolbar: true))
            }

            windowGroup(model: appModel, module: .weather) { selection in
                appModel.weatherRoot.viewController.viewer(root: appModel.weatherRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: closeButton, addToolbar: true))
            }

            WindowGroup("Generator Adventure", id: WindowIdentifier.generateAdventure.rawValue, for: WindowItemSelection.self) { $selection in
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.adventureRoot.viewController.generatorView(root: appModel.adventureRoot, selection: selection ?? WindowItemSelection(itemId: UUID()))
                        .modifier(WindowViewerSetUpViewModifier(model: appModel, module: .adventure))
                }
            }
            .windowResizability(.contentSize)
            .defaultWindowPlacementAll(.below(WindowIdentifier.game.rawValue))
    #if !os(iOS)
            .restorationBehavior(.disabled)
    #endif

            WindowGroup("Map Edit Viewer", id: WindowIdentifier.mapEditor.rawValue) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.mapRoot.viewController.mapEditWindow(root: appModel.mapRoot)
                        .modifier(WindowViewerSetUpViewModifier(model: appModel, module: .map))
                }
            }
            .windowResizability(.contentSize)
            .defaultWindowPlacementAll(.below(WindowIdentifier.game.rawValue))
    #if !os(iOS)
            .restorationBehavior(.disabled)
    #endif

            BaseWindow("Logs", id: WindowIdentifier.logs.rawValue) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.gameRoot.viewController.logWindow()
                }
            }
            .windowResizability(.contentSize)
            .defaultWindowPlacementAll(.above(WindowIdentifier.game.rawValue))
    #if !os(iOS)
            .restorationBehavior(.disabled)
    #endif

            BaseWindow("Editor", id: WindowIdentifier.editor.rawValue) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    AppModeRouteType.editor
                        .setAppSizeMode()
                        .environmentSetUp(appModel)
                        .frame(minWidth: 1000, minHeight: 600)
                }
            }
            .windowResizability(.contentSize)
            .defaultWindowPlacementAll(.leading(WindowIdentifier.game.rawValue))
#if !os(iOS)
        .restorationBehavior(.disabled)
#endif
#if os(macOS)
            .keyboardShortcut("E", modifiers: [.command, .shift, .option])
#endif
            
            BaseWindow("Search", id: WindowIdentifier.search.rawValue) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    NavigationSplitView {
                        GameFactory.rootSearchView(root: appModel.gameRoot, navigator: appModel.navigator)
                    } detail: {
                        GameFactory.detailSearchView(root: appModel.gameRoot, navigator: appModel.navigator)
                    }
                    .setAppSizeMode()
                    .environmentSetUp(appModel)
                    .frame(minWidth: 1000, minHeight: 600)
                }
            }
            .windowResizability(.contentSize)
            .defaultWindowPlacementAll(.trailing(WindowIdentifier.game.rawValue))
#if !os(iOS)
        .restorationBehavior(.disabled)
#endif
#if os(macOS)
            .keyboardShortcut("S", modifiers: [.command, .shift, .option])
#endif
        }
        .defaultSize(CGSize(width: 600, height: 800))
    }
    
    private func windowGroup<Content: View>(model: AppModel, module: NetworkModules, content: @escaping (WindowItemSelection) -> Content) -> some Scene {
        WindowGroup("\(module.title) Viewer", id: module.viewerWindowId, for: WindowItemSelection.self) { $selection in
            DataBaseAppStoreAvailable(appModel: appModel) { _ in
                ManagedNavigationStack(name: "\(module.title) Viewer") {
                    content(selection ?? WindowItemSelection(itemId: UUID()))
                }
                .modifier(WindowViewerSetUpViewModifier(model: model, module: module))
            }
        }
        .windowResizability(.contentSize)
        .defaultWindowPlacementAll(model.windowPlacement(for: module))
#if !os(iOS)
        .restorationBehavior(.disabled)
#endif
    }
    
    private var closeButton: Bool {
        #if os(macOS)
        return false
        #else
        return true
        #endif
    }
}

struct WindowViewerSetUpViewModifier: ViewModifier {
    let model: AppModel
    let module: NetworkModules
    
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .resetAppColorScheme()
            .frame(minWidth: 600, minHeight: 400)
            .handlesExternalEvents(preferring: [], allowing: [])
            .tint(module.tint)
            .accentColor(module.tint)
            .environmentSetUp(model)
            .environment(\.networkActions, model.gameRoot.networkActions())
            .environment(\.sharingControlActions, model.gameRoot.sharingControlActions)
            .environment(\.sharingFeatureActions, model.gameRoot.sharingFeatureActions)
#if os(macOS)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
#endif
    }
}

#endif
