// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

/// Main-tab (adventure / character sheet) menu behaviour, moved out of `OverlayGameMenu` so it has
/// a test seam. See CODE_AUDIT_17 §8.4.
extension GameScreenModel {
    /// Simple show/hide toggle for iOS/tvOS: persists the choice and updates the shown tab.
    func applyMainTabToggle(isShown: Bool, isMaster: Bool, settings: AppSettingsModel, animated: Bool) {
        if isMaster {
            settings.autoShowMasterMainTab = isShown
        } else {
            settings.autoShowPlayerMainTab = isShown
        }

        withAnimation(animated ? .default : nil) {
            showMainTab = isShown ? Self.inlineMainTab(isMaster: isMaster) : .none
        }
    }

    /// Three-state display mode (hidden / inline / window): persists the mode, updates the inline
    /// tab and opens or closes the matching viewer window.
    func applyMainTabDisplayMode(
        _ newValue: GameMainTabDisplayMode,
        isMaster: Bool,
        settings: AppSettingsModel,
        scenes: ScenesManager,
        selectedItemId: UUID?
    ) {
        if isMaster {
            settings.masterMainTabDisplayMode = newValue.rawValue
        } else {
            settings.playerMainTabDisplayMode = newValue.rawValue
        }

        let viewerScene = isMaster ? SceneId.adventureViewer : SceneId.valueViewer
        switch newValue {
        case .hidden:
            showMainTab = .none
            closeIfOpen(viewerScene, scenes: scenes)
        case .inline:
            showMainTab = Self.inlineMainTab(isMaster: isMaster)
            closeIfOpen(viewerScene, scenes: scenes)
        case .window:
            showMainTab = .none
            #if os(macOS) || os(visionOS)
            if scenes.getSceneState(for: viewerScene) == .closed, let selectedItemId {
                scenes.openWindow(
                    SceneId.viewerId(for: isMaster ? .adventure : .value),
                    selection: WindowItemSelection(itemId: selectedItemId)
                )
            }
            #endif
        }
    }

    private static func inlineMainTab(isMaster: Bool) -> NetworkModules {
        isMaster ? .game : .value
    }

    private func closeIfOpen(_ scene: SceneId, scenes: ScenesManager) {
        if scenes.getSceneState(for: scene) == .opened {
            scenes.dismissWindow(scene)
        }
    }
}
