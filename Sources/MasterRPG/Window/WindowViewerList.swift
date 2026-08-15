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
import RuleRPG
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

            windowGroup(model: appModel, module: .rule) { selection in
                appModel.ruleRoot.viewController.viewer(root: appModel.ruleRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: closeButton, addToolbar: true))
            }

            // visionOS has no 2D window for 3D objects — SpaceRPG's ImmersiveSpace
            // (SceneId.spaceViewer, registered in WindowVisionList) is the only
            // surface for viewing a Space item there. See the visionOS-gated
            // `openSpaceViewer` calls in OpenFileWindowView, ItemPrimaryAction, and
            // SpaceRPG's InlineRowViewer.
#if !os(visionOS)
            windowGroup(model: appModel, module: .space) { selection in
                appModel.spaceRoot.viewController.viewer(root: appModel.spaceRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: closeButton, addToolbar: true))
            }
#endif

            windowGroup(model: appModel, module: .table) { selection in
                appModel.tableRoot.viewController.viewer(root: appModel.tableRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: closeButton, addToolbar: true))
            }

            windowGroup(model: appModel, module: .weather) { selection in
                appModel.weatherRoot.viewController.viewer(root: appModel.weatherRoot, itemId: selection.itemId, configuration: ViewerConfiguration(closeButton: closeButton, addToolbar: true))
            }
        }
        .defaultSize(CGSize(width: 600, height: 800))
    }
    
    private func windowGroup<Content: View>(model: AppModel, module: NetworkModules, content: @escaping (WindowItemSelection) -> Content) -> some Scene {
        WindowGroup("\(module.title) Viewer", id: module.viewerWindowId, for: WindowItemSelection.self) { $selection in
            DataBaseAppStoreAvailable(appModel: appModel) { _ in
                ManagedNavigationStack(name: "\(module.title) Viewer") {
                    content(selection ?? WindowItemSelection(itemId: UUID()))
                }
                .sceneTracker(for: SceneId.viewerId(for: module))
                .modifier(WindowViewerSetUpViewModifier(model: model, module: module))
            }
            .environment(model.scenesManager)
            .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultWindowPlacementAll(model.windowPlacement(for: module))
        .restorationBehaviorAll(.disabled)
    }
    
#if os(macOS)
    private let closeButton = false
#else
    private let closeButton = true
#endif
}

struct WindowViewerSetUpViewModifier: ViewModifier {
    let model: AppModel
    let module: NetworkModules
    let showsWindowToolbarBackground: Bool
    /// True only for visionOS ImmersiveSpace content. Skips the 2D-window-only
    /// bits — a fixed minWidth/minHeight frame and an opaque themed background
    /// behind it render as a solid floating rectangle in the space instead of
    /// leaving passthrough/mixed reality visible around the 3D content.
    let isImmersiveSpace: Bool

    init(
        model: AppModel,
        module: NetworkModules,
        showsWindowToolbarBackground: Bool = false,
        isImmersiveSpace: Bool = false
    ) {
        self.model = model
        self.module = module
        self.showsWindowToolbarBackground = showsWindowToolbarBackground
        self.isImmersiveSpace = isImmersiveSpace
    }

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .resetAppColorScheme()
            .applyIf(!isImmersiveSpace) {
                $0.frame(minWidth: 600, minHeight: 400)
                    .handlesExternalEvents(preferring: [], allowing: [])
            }
            .moduleTint(module)
            .environmentSetUp(model)
            .environmentActionSetUp(model)
            .modifier(UserSettingsViewModifier(appModel: model, appliesBackground: !isImmersiveSpace))
#if os(macOS)
            .toolbarBackgroundVisibility(
                showsWindowToolbarBackground ? .visible : .hidden,
                for: .windowToolbar
            )
#endif
    }
}

#endif
