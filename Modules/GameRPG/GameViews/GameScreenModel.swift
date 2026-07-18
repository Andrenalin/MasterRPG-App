
import CoreRPG
import SwiftUI

@MainActor @Observable
final class GameScreenModel {

    static let mapOverlaySpacing: CGFloat = 8
    
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
    var showsBattleRoundAnnouncement: Bool = false

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

    /// The actual rendered width of the inline adventure/character overlay.
    /// This is deliberately presentation metadata: it must never become a
    /// frame constraint on the full-window game surface or its chrome.
    private(set) var inlineMainOverlayWidth: CGFloat = 0
    private(set) var topGameMenuHeight: CGFloat = 0

    var mapTrailingViewportReservation: CGFloat {
        guard showMainTab != .none, inlineMainOverlayWidth > 0 else { return 0 }
        return inlineMainOverlayWidth + Self.mapOverlaySpacing
    }

    func updateInlineMainOverlayWidth(_ width: CGFloat) {
        let width = width.isFinite ? max(0, width) : 0
        guard inlineMainOverlayWidth != width else { return }
        inlineMainOverlayWidth = width
    }

    func updateTopGameMenuHeight(_ height: CGFloat) {
        let height = height.isFinite ? max(0, height) : 0
        guard topGameMenuHeight != height else { return }
        topGameMenuHeight = height
    }

}
