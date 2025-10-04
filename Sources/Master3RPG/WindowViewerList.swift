// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import RolePlayGameKit
import SwiftUI

import AdventureRPG
import AudioRPG
import CharacterRPG
import DiceRPG
import GeneratorRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG


struct WindowViewerList: Scene {
    let appModel: AppModel
    
    var body: some Scene {
        Group {
            windowGroup(model: appModel, module: .generator) { selection in
                appModel.generatorRoot.viewController.windowViewer(root: appModel.generatorRoot, selection: selection)
            }

            windowGroup(model: appModel, module: .pdf) { selection in
                appModel.pdfRoot.viewController.windowViewer(root: appModel.pdfRoot, selection: selection)
            }

            windowGroup(model: appModel, module: .table) { selection in
                appModel.tableRoot.viewController.windowViewer(root: appModel.tableRoot, selection: selection)
            }

            windowGroup(model: appModel, module: .weather) { selection in
                appModel.weatherRoot.viewController.windowViewer(root: appModel.weatherRoot, selection: selection)
            }
        }
        .defaultSize(CGSize(width: 600, height: 800))
    }
    
    private func windowGroup<Content: View>(model: AppModel, module: NetworkModules, content: @escaping (WindowItemSelection) -> Content) -> some Scene {
        WindowGroup("\(module.title) Viewer", id: module.viewerkWindowId, for: WindowItemSelection.self) { $selection in
            content(selection ?? WindowItemSelection(itemId: UUID()))
                .modifier(WindowViewerSetUpViewModifier(model: model, module: module))
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
