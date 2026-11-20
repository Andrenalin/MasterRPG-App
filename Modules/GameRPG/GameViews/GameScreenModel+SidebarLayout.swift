// @copyright André Trettin

import CoreRPG
import Foundation

/// How the game master's iPad sidebar arranges its views.
enum GameSidebarLayout: Int, CaseIterable, Identifiable {
    /// One view at a time in the sidebar column.
    case single
    /// The Game View on top, the Other View or Battle Round below it.
    case horizontal
    /// The Game View on the leading side, the Other View or Battle Round next to it.
    case vertical

    var id: Int { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .single: LocalizedStringResource("Single Layout", bundle: .module)
        case .horizontal: LocalizedStringResource("Horizontal Layout", bundle: .module)
        case .vertical: LocalizedStringResource("Vertical Layout", bundle: .module)
        }
    }

    var systemImage: String {
        switch self {
        case .single: "rectangle"
        case .horizontal: "rectangle.split.1x2"
        case .vertical: "rectangle.split.2x1"
        }
    }
}

/// Where the sidebar sits on the iPhone.
enum GameSidebarPlacement: Int, CaseIterable, Identifiable {
    /// Beside the game screen, on the trailing edge.
    case trailing
    /// Below the game screen, taking half of its height.
    case bottom

    var id: Int { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .trailing: LocalizedStringResource("Trailing Layout", bundle: .module)
        case .bottom: LocalizedStringResource("Bottom Layout", bundle: .module)
        }
    }

    var systemImage: String {
        switch self {
        case .trailing: "rectangle.righthalf.inset.filled"
        case .bottom: "rectangle.bottomhalf.inset.filled"
        }
    }
}

extension GameScreenModel {
    var isBottomSidebar: Bool {
        sidebarPlacement == .bottom
    }

    /// The share of the screen height the bottom panel takes.
    var bottomSidebarHeightFraction: CGFloat {
        isLargeBottomSidebar ? 2.0 / 3.0 : 0.5
    }

    /// Whether the sidebar is in its enlarged size: wider on the trailing edge, taller at the bottom.
    var isSidebarEnlarged: Bool {
        isBottomSidebar ? isLargeBottomSidebar : isLargeSideBar
    }

    func toggleSidebarSize() {
        if isBottomSidebar {
            isLargeBottomSidebar.toggle()
        } else {
            toggleSideBarWidth()
        }
    }

    func updateBottomPanelHeight(_ height: CGFloat) {
        let height = height.isFinite ? max(0, height) : 0
        guard bottomPanelHeight != height else { return }
        bottomPanelHeight = height
    }

    /// The part of the map viewport the shown bottom panel covers. As for the trailing
    /// placement, only the Game View and the Battle Round reserve space; the module list
    /// overlays the map.
    var mapBottomViewportReservation: CGFloat {
        guard isBottomSidebar,
              showMainTab != .none || showsBattleRoundSidebar,
              bottomPanelHeight > 0 else { return 0 }
        return bottomPanelHeight + Self.mapOverlaySpacing
    }

    /// The height of the bottom panel while any view is shown in it, else 0. Controls that sit at
    /// the bottom of the game screen (the map toolbar, the quick dice toggle) rise above it.
    var visibleBottomPanelHeight: CGFloat {
        isBottomSidebar && isInlineSidebarVisible ? bottomPanelHeight : 0
    }

    /// The quick dice toggle button sits above a shown bottom panel.
    var quickDiceToggleBottomReservation: CGFloat {
        visibleBottomPanelHeight
    }

    /// How far the bottom toolbar (map controls) rises above a shown bottom panel.
    var toolBarBottomReservation: CGFloat {
        let height = visibleBottomPanelHeight
        return height > 0 ? height + Self.mapOverlaySpacing : 0
    }

    /// The Game View the split layouts always show first. They are for the game master only.
    static let splitPrimaryModule: NetworkModules = .game

    var isSplitSidebar: Bool {
        sidebarLayout != .single
    }

    /// Both slots of a split layout are showing.
    var isSplitSidebarVisible: Bool {
        isSplitSidebar && showMainTab != .none && (showSettingTab != .none || showsBattleRoundSidebar)
    }

    /// The rendered width of the whole inline sidebar: two columns side by side in the vertical
    /// layout, else the one column's.
    var inlineSidebarWidth: CGFloat {
        guard sidebarLayout == .vertical, isSplitSidebarVisible else { return inlineMainOverlayWidth }
        return inlineMainOverlayWidth * 2 + Self.mapOverlaySpacing
    }

    /// A shown split sidebar always has a second view: the remembered one.
    func ensureSplitSecondary() {
        guard showSettingTab == .none, !showsBattleRoundSidebar else { return }
        if splitSecondaryIsBattle {
            showsBattleRoundSidebar = true
        } else {
            showSettingTab = .setting
        }
    }

    /// Hiding the Game View hides the whole split sidebar.
    func hideSplitSecondary() {
        showSettingTab = .none
        showsBattleRoundSidebar = false
    }

    func applySidebarLayoutChange() {
        if isSplitSidebar {
            guard isInlineSidebarVisible else { return }
            if showMainTab == .none {
                showMainTab = Self.splitPrimaryModule
            } else {
                ensureSplitSecondary()
            }
        } else if showMainTab != .none {
            // One slot again: the Game View stays.
            showSettingTab = .none
            showsBattleRoundSidebar = false
        }
    }
}
