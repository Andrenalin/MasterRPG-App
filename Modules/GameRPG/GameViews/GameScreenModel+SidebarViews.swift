// @copyright André Trettin

import CoreRPG

/// The iOS sidebar content switches (primary view, other view, battle round), shared by the
/// compact sidebar menu and the regular-width button column. Callers wrap them in `withAnimation`.
extension GameScreenModel {
    func setSidebarPrimaryView(_ isOn: Bool, primaryModule: NetworkModules, allowsPrimaryView: Bool) {
        guard allowsPrimaryView else { return }
        if isSplitSidebar {
            // The Game View is the split's first slot: off hides the whole sidebar.
            showMainTab = isOn ? primaryModule : .none
            showMainTabIOS = isInlineSidebarVisible
            return
        }
        iOSSidebarShowsPrimaryView = isOn
        showMainTab = isOn ? primaryModule : .none
        showMainTabIOS = isInlineSidebarVisible
    }

    func setSidebarOtherView(_ isOn: Bool) {
        if isSplitSidebar {
            // The split's second slot switches between Other View and Battle Round.
            guard isOn else { return }
            showSettingTab = .setting
            showMainTabIOS = isInlineSidebarVisible
            return
        }
        iOSSidebarShowsPrimaryView = !isOn
        showSettingTab = isOn ? .setting : .none
        showMainTabIOS = isInlineSidebarVisible
    }

    func setSidebarBattleRound(_ isOn: Bool) {
        if isSplitSidebar {
            guard isOn else { return }
            showsBattleRoundSidebar = true
            showMainTabIOS = isInlineSidebarVisible
            return
        }
        showsBattleRoundSidebar = isOn
        showMainTabIOS = isInlineSidebarVisible
    }
}
