
import CoreRPG
import SwiftUI

@MainActor @Observable
final class GameScreenModel {

    static let mapOverlaySpacing: CGFloat = 8
    static let chromeHorizontalPadding: CGFloat = 4

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

    var isSideMenuVisible: Bool = true

    /// Owned so it stays derived from `showMainTab` instead of being toggled
    /// separately by each call site — `showMainTab` changes from several
    /// places (window restore, tab buttons, the sidebar menu), and a
    /// second, manually-set flag drifted out of sync with those. `TableSheetView`
    /// reads this to detach its `.searchable` toolbar item, since the sidebar's
    /// content view stays mounted (just hidden via opacity/offset) rather than
    /// being removed from the tree.
    @ObservationIgnored let searchBarVisibleModel = SearchBarVisibleModel()

    var showMainTab: NetworkModules = .none {
        didSet {
            if showMainTab == .none, !showsBattleRoundSidebar {
                isSideMenuVisible = true
            } else if showMainTab != .none {
                showSettingTab = .none
                showsBattleRoundSidebar = false
            }
            searchBarVisibleModel.isVisible = showMainTab != .none
        }
    }

    var showSettingTab: NetworkModules = .none {
        didSet {
            guard showSettingTab != .none else { return }
            showMainTab = .none
            showsBattleRoundSidebar = false
        }
    }
    func resetToSettingsTab(toggle: Bool = true) {
        if toggle || showSettingTab == .none {
            showSettingTab = showSettingTab == .setting ? .none : .setting
        }
        showMainTab = .none
    }

    
    // Game main tab display mode (for macOS/visionOS three-state button)
    var gameMainTabDisplayMode: GameMainTabDisplayMode = .hidden
    
    // Simple show/hide state for iOS/tvOS
    var showMainTabIOS: Bool = false

    // Retains the selected iOS sidebar content while the sidebar is hidden.
    var iOSSidebarShowsPrimaryView: Bool = true

    /// Battle management uses the same inline sidebar slot as the Adventure,
    /// Character, and module-list content. Keeping this state separate from
    /// `NetworkModules` avoids adding a presentation-only case to the network
    /// protocol while the property observers preserve exclusive presentation.
    var showsBattleRoundSidebar: Bool = false {
        didSet {
            guard showsBattleRoundSidebar else { return }
            showMainTab = .none
            showSettingTab = .none
        }
    }

    var isInlineSidebarVisible: Bool {
        showMainTab != .none || showSettingTab != .none || showsBattleRoundSidebar
    }

    func toggleBattleRoundSidebar() {
        showsBattleRoundSidebar.toggle()
    }

    func hideInlineSidebar() {
        showMainTab = .none
        showSettingTab = .none
        showsBattleRoundSidebar = false
    }

    /// The actual rendered width of the inline adventure/character overlay.
    /// This is deliberately presentation metadata: it must never become a
    /// frame constraint on the full-window game surface or its chrome.
    private(set) var inlineMainOverlayWidth: CGFloat = 0
    private(set) var topGameMenuHeight: CGFloat = 0

    var mapTrailingViewportReservation: CGFloat {
        guard (showMainTab != .none || showsBattleRoundSidebar),
              inlineMainOverlayWidth > 0 else { return 0 }
        return inlineMainOverlayWidth + Self.mapOverlaySpacing
    }

    func updateInlineMainOverlayWidth(_ width: CGFloat) {
        let width = width.isFinite ? max(0, width) : 0
        guard inlineMainOverlayWidth != width else { return }
        inlineMainOverlayWidth = width
    }

    /// The window's safe-area insets around the game chrome. The iOS side panel ignores
    /// the safe area, so it reads zero itself; the chrome measures them for it.
    private(set) var chromeTopSafeAreaInset: CGFloat = 0
    private(set) var chromeTrailingSafeAreaInset: CGFloat = 0

    /// Screen-space top edge for the side panel's content: one spacing step below the
    /// top menu, which overlaps the panel in the compact layout.
    var sidePanelContentTop: CGFloat {
        chromeTopSafeAreaInset + topGameMenuHeight + Self.mapOverlaySpacing
    }

    /// The part of the visible side panel that overlaps the top menu's row. The panel
    /// runs to the screen edge, the menu stops at the safe area and the chrome padding.
    var topMenuTrailingReservation: CGFloat {
        guard isInlineSidebarVisible else { return 0 }
        return max(0, inlineMainOverlayWidth - chromeTrailingSafeAreaInset - Self.chromeHorizontalPadding)
    }

    func updateChromeSafeAreaInsets(top: CGFloat, trailing: CGFloat) {
        let top = top.isFinite ? max(0, top) : 0
        let trailing = trailing.isFinite ? max(0, trailing) : 0
        if chromeTopSafeAreaInset != top { chromeTopSafeAreaInset = top }
        if chromeTrailingSafeAreaInset != trailing { chromeTrailingSafeAreaInset = trailing }
    }

    func updateTopGameMenuHeight(_ height: CGFloat) {
        let height = height.isFinite ? max(0, height) : 0
        guard topGameMenuHeight != height else { return }
        topGameMenuHeight = height
    }

#if os(macOS)
    /// Starts the main tab in the display mode saved in settings (raw `GameMainTabDisplayMode`).
    /// Returns `true` when the tab opens in its own window, which the caller then opens.
    /// Shared by the game-master and player screens. See CODE_AUDIT_19 §9.19.
    func restoreMainTab(savedMode rawValue: Int, tab: NetworkModules, animation: Animation?) -> Bool {
        let savedMode = GameMainTabDisplayMode(rawValue: rawValue) ?? .hidden
        gameMainTabDisplayMode = savedMode
        withAnimation(animation) {
            showMainTab = savedMode == .inline ? tab : .none
        }
        return savedMode == .window
    }
#endif
}
