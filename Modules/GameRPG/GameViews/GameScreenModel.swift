
import CoreRPG
import SwiftUI

@MainActor @Observable
final class GameScreenModel {

    static let mapOverlaySpacing: CGFloat = 8
    static let chromeHorizontalPadding: CGFloat = 4
    /// Space below the quick dice overlay and its toggle button.
    static let quickDiceBottomInset: CGFloat = {
#if os(macOS)
        4
#else
        0
#endif
    }()
    /// The quick dice toggle sits this far further from the trailing edge than the overlay
    /// does on macOS, so its glass circle lines up with the overlay's own padding.
    static let quickDiceToggleTrailingInset: CGFloat = {
#if os(macOS)
        2
#else
        0
#endif
    }()

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
    var showQuickDice: Bool = false
    var showExport: Bool = false
    var showQuitGameAlert: Bool = false
    var showsBattleRoundAnnouncement: Bool = false

    var isSideMenuVisible: Bool = true

    /// The effective sidebar layout. The screen sets it from the game master's saved choice and
    /// keeps it `.single` wherever the split layouts are not offered (see `GameSidebarLayout`).
    var sidebarLayout: GameSidebarLayout = .single {
        didSet {
            guard oldValue != sidebarLayout else { return }
            applySidebarLayoutChange()
        }
    }

    /// Where the sidebar sits. The screen sets it from the saved choice and keeps it `.trailing`
    /// wherever the bottom placement is not offered (everywhere but the iPhone).
    var sidebarPlacement: GameSidebarPlacement = .trailing

    /// The window is at compact width (the iPhone). The screen sets it with the sidebar placement.
    var isCompactWidth: Bool = false

    /// The bottom placement's panel takes two thirds of the screen height instead of half.
    var isLargeBottomSidebar: Bool = false

    /// The rendered height of the bottom placement's panel. Like `inlineMainOverlayWidth`,
    /// presentation metadata for the viewport reservation, never a layout constraint.
    var bottomPanelHeight: CGFloat = 0

    /// Which view the split layouts' second slot shows when they open: the Other View or the
    /// Battle Round, whichever was shown last.
    var splitSecondaryIsBattle: Bool = false

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
            if showMainTab == .none, isSplitSidebar {
                hideSplitSecondary()
            }
            if showMainTab == .none, !showsBattleRoundSidebar {
                isSideMenuVisible = true
            } else if showMainTab != .none {
                if isSplitSidebar {
                    ensureSplitSecondary()
                } else {
                    showSettingTab = .none
                    showsBattleRoundSidebar = false
                }
            }
            searchBarVisibleModel.isVisible = showMainTab != .none
        }
    }

    var showSettingTab: NetworkModules = .none {
        didSet {
            guard showSettingTab != .none else { return }
            splitSecondaryIsBattle = false
            if isSplitSidebar {
                showsBattleRoundSidebar = false
                if showMainTab == .none { showMainTab = Self.splitPrimaryModule }
            } else {
                showMainTab = .none
                showsBattleRoundSidebar = false
            }
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
            guard showsBattleRoundSidebar else {
                // The battle panel closing leaves the split's second slot to the Other View.
                if isSplitSidebar, showMainTab != .none, showSettingTab == .none {
                    showSettingTab = .setting
                }
                return
            }
            splitSecondaryIsBattle = true
            if isSplitSidebar {
                showSettingTab = .none
                if showMainTab == .none { showMainTab = Self.splitPrimaryModule }
            } else {
                showMainTab = .none
                showSettingTab = .none
            }
        }
    }

    var isInlineSidebarVisible: Bool {
        showMainTab != .none || showSettingTab != .none || showsBattleRoundSidebar
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
        guard !isBottomSidebar,
              (showMainTab != .none || showsBattleRoundSidebar),
              inlineMainOverlayWidth > 0 else { return 0 }
        return inlineSidebarWidth + Self.mapOverlaySpacing
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
    private(set) var chromeBottomSafeAreaInset: CGFloat = 0

    /// Screen-space top edge for the side panel's content: one spacing step below the
    /// top menu, which overlaps the panel in the compact layout.
    var sidePanelContentTop: CGFloat {
        chromeTopSafeAreaInset + topGameMenuHeight + Self.mapOverlaySpacing
    }

    /// The part of the visible side panel that overlaps the top menu's row. The panel
    /// runs to the screen edge, the menu stops at the safe area and the chrome padding.
    var topMenuTrailingReservation: CGFloat {
        guard isInlineSidebarVisible, !isBottomSidebar else { return 0 }
        return max(0, inlineSidebarWidth - chromeTrailingSafeAreaInset - Self.chromeHorizontalPadding)
    }

    func updateChromeSafeAreaInsets(top: CGFloat, trailing: CGFloat, bottom: CGFloat = 0) {
        let top = top.isFinite ? max(0, top) : 0
        let trailing = trailing.isFinite ? max(0, trailing) : 0
        let bottom = bottom.isFinite ? max(0, bottom) : 0
        if chromeTopSafeAreaInset != top { chromeTopSafeAreaInset = top }
        if chromeTrailingSafeAreaInset != trailing { chromeTrailingSafeAreaInset = trailing }
        if chromeBottomSafeAreaInset != bottom { chromeBottomSafeAreaInset = bottom }
    }

    /// The rendered height of the quick dice overlay at the bottom trailing edge.
    private(set) var quickDiceOverlayHeight: CGFloat = 0

    /// How far the sidebar stops short of the bottom edge to leave room for the quick dice overlay.
    /// See CODE_AUDIT_Since_3.0.1 §5.14.
    var quickDiceBottomReservation: CGFloat {
        // Above a bottom panel, not inside it: the panel keeps its full height.
        guard showQuickDice, quickDiceOverlayHeight > 0, !isBottomSidebar else { return 0 }
        return quickDiceOverlayHeight + chromeBottomSafeAreaInset + Self.quickDiceBottomInset + Self.mapOverlaySpacing
    }

    /// How much of the trailing edge the quick dice toggle button leaves free, so it sits on the
    /// bottom leading side of whatever is at the trailing edge: the quick dice overlay, else the
    /// inline sidebar, else nothing (the button is at the trailing screen edge).
    var quickDiceToggleTrailingReservation: CGFloat {
        if isBottomSidebar {
            // Beside the overlay, which sits above a shown bottom panel.
            return showQuickDice ? sideBarWidth : 0
        }
        if showQuickDice { return sideBarWidth }
        if isInlineSidebarVisible, inlineMainOverlayWidth > 0 { return inlineSidebarWidth }
        return 0
    }

    func updateQuickDiceOverlayHeight(_ height: CGFloat) {
        let height = height.isFinite ? max(0, height) : 0
        guard quickDiceOverlayHeight != height else { return }
        quickDiceOverlayHeight = height
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
