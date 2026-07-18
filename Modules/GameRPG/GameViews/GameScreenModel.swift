
import CoreRPG
import SwiftUI

@MainActor @Observable
final class GameScreenModel {

    static let mapSidebarSpacing: CGFloat = 12
    
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

#if os(iOS) || os(macOS)
    /// Keeps the expensive RealityKit scene reusable while the 2D map is
    /// selected. The active controller reference lives on `GameRootModel`
    /// only while the 3D surface is actually visible.
    var retainedGameTableModel: GameTableModel?
#endif

    var isSideMenuVisible: Bool = true

    var showMainTab: NetworkModules = .none {
        didSet {
            if showMainTab == .none {
                isSideMenuVisible = true
            }
        }
    }
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
    
    // Game main tab display mode (for macOS/visionOS three-state button)
    var gameMainTabDisplayMode: GameMainTabDisplayMode = .hidden
    
    // Simple show/hide state for iOS/tvOS
    var showMainTabIOS: Bool = false

    // Retains the selected iOS sidebar content while the sidebar is hidden.
    var iOSSidebarShowsPrimaryView: Bool = true

    var isInlineSidebarVisible: Bool {
        showMainTab != .none || showSettingTab != .none
    }

    func mapTrailingReservation(usesInlineSidebarLayout: Bool) -> CGFloat {
        guard usesInlineSidebarLayout, isInlineSidebarVisible else { return 0 }
        return sideBarWidth + Self.mapSidebarSpacing
    }
}
