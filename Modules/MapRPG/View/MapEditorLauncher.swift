// @copyright André Trettin

import CoreRPG

import SwiftUI

/// The two editors a map offers: the full map editor and the cover-tile editor. One place decides
/// the route and the window of each and what has to be selected before a window opens, so the
/// toolbar buttons and the display configuration cannot drift apart again.
/// See CODE_AUDIT_26 §5.23.
enum MapEditorKind: Equatable {
    case map
    case tile

    /// The destination of the navigation stack (iOS, tvOS).
    func route(for mapId: UUID) -> MapEditorRoute {
        switch self {
        case .map: .mapEditor(mapId)
        case .tile: .mapTileEditor(mapId)
        }
    }

    /// The window (macOS, visionOS).
    var sceneId: SceneId {
        switch self {
        case .map: .mapEditor
        case .tile: .mapTileEditor
        }
    }

    /// Opens this editor for `model`. A window shows the item selected in the editor model, which
    /// is set to `model` before it opens; the navigation stack carries the id in its route.
    @MainActor
    func open(model: MapModel, root: MapRootModel, navigator: Navigator, scenesManager: ScenesManager) {
#if os(visionOS) || os(macOS)
        root.editController.editorModel.sheetEditorModel.itemId = model.id
        scenesManager.openWindow(sceneId)
#else
        navigator.navigate(to: route(for: model.id))
#endif
    }
}
