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
                appModel.adventureRoot.viewController.windowViewer(root: appModel.adventureRoot, selection: selection)
            }

            windowGroup(model: appModel, module: .value) { selection in
                appModel.characterRoot.viewController.windowViewer(root: appModel.characterRoot, selection: selection)
            }
            
            windowGroup(model: appModel, module: .generator) { selection in
                appModel.generatorRoot.viewController.windowViewer(root: appModel.generatorRoot, selection: selection)
            }

            windowGroup(model: appModel, module: .map) { selection in
                appModel.mapRoot.viewController.windowViewer(root: appModel.mapRoot, selection: selection)
            }

            windowGroup(model: appModel, module: .pdf) { selection in
                appModel.pdfRoot.viewController.windowViewer(root: appModel.pdfRoot, selection: selection)
            }

            windowGroup(model: appModel, module: .photo) { selection in
                appModel.photoRoot.viewController.windowViewer(root: appModel.photoRoot, selection: selection)
            }

            windowGroup(model: appModel, module: .space) { selection in
                appModel.spaceRoot.viewController.windowViewer(root: appModel.spaceRoot, selection: selection)
            }
            
            windowGroup(model: appModel, module: .table) { selection in
                appModel.tableRoot.viewController.windowViewer(root: appModel.tableRoot, selection: selection)
            }

            windowGroup(model: appModel, module: .weather) { selection in
                appModel.weatherRoot.viewController.windowViewer(root: appModel.weatherRoot, selection: selection)
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
            .environment(\.gameModus, model.settingsModel.gameModus)
            .environment(\.networkActions, model.gameRoot.networkActions())
            .environment(\.sharingControlActions, model.gameRoot.sharingControlActions)
            .environment(\.sharingFeatureActions, model.gameRoot.sharingFeatureActions)
            .environment(\.showGame, model.settingsModel.showGame)
#if os(macOS)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
#endif
    }
}

#endif
