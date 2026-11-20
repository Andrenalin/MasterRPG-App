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

extension GameScreenModel {
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
