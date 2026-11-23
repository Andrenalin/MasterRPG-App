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

    private static func inlineMainTab(isMaster: Bool) -> NetworkModules {
        isMaster ? .game : .value
    }
}
