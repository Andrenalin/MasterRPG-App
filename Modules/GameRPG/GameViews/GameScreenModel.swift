// @copyright André Trettin

import CoreRPG
import SwiftUI

@Observable
final class GameScreenModel {
    
    private enum WidthValues {
#if os(macOS)
        static let small: CGFloat = 350
        static let large: CGFloat = 500
#elseif os(tvOS)
        static let small: CGFloat = 600
        static let large: CGFloat = 750
#else
        static let small: CGFloat = 300
        static let large: CGFloat = 400
#endif
    }
    var sideBarWidth: CGFloat = WidthValues.small
    func toggleSideBarWidth() {
        sideBarWidth = sideBarWidth == WidthValues.large ? WidthValues.small : WidthValues.large
    }
    var isLargeSideBar: Bool {
        sideBarWidth == WidthValues.large
    }

    var showDice: Bool = false
    var showExport: Bool = false
    var showQuitGameAlert: Bool = false
    
    var showMainTab: NetworkModules =  .none
    func resetToMainTab(toggle: Bool = true) {
        if toggle || showMainTab == .none {
            showMainTab = showMainTab == .game ? .none : .game
        }
        showSettingTab = .none
    }

    var showSettingTab: NetworkModules = .none
    func resetToSettingsTab(toggle: Bool = true) {
        if toggle || showSettingTab == .none {
            showSettingTab = showSettingTab == .setting ? .none : .setting
        }
        showMainTab = .none
    }

    var showGameType: NetworkModules = .none
    var showSettingsType: NetworkModules = .none
}
