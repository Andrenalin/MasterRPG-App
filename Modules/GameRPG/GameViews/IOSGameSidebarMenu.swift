// @copyright André Trettin

#if os(iOS)
import CoreRPG
import SwiftUI

struct IOSGameSidebarMenu: View {
    let isMaster: Bool
    let allowsPrimaryView: Bool

    @Environment(AppSettingsModel.self) private var appSettingsModel
    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        let glass: Glass = if isSidebarVisible {
            .regular.tint(theme.tint(for: .game).opacity(0.7)).interactive()
        } else {
            .regular.interactive()
        }

        Menu {
            Toggle(isOn: sidebarVisibilityBinding) {
                Label {
                    Text("Sidebar", bundle: .module)
                } icon: {
                    Image(systemName: "sidebar.right")
                }
            }

            Button {
                withAnimation(accessibilityReduceMotion ? nil : .default) {
                    gameScreenModel.toggleSideBarWidth()
                }
            } label: {
                Label {
                    Text(
                        gameScreenModel.isLargeSideBar ? "Reduce Sidebar" : "Enlarge Sidebar",
                        bundle: .module
                    )
                } icon: {
                    Image(
                        systemName: gameScreenModel.isLargeSideBar
                            ? "square.resize.down"
                            : "square.resize.up"
                    )
                }
            }
            .disabled(!isSidebarVisible)

            Divider()

            Toggle(isOn: primaryViewBinding) {
                Label {
                    Text(primaryViewTitle)
                } icon: {
                    Image(systemName: primaryModule.icon)
                }
            }
            .disabled(!allowsPrimaryView)

            Toggle(isOn: otherViewBinding) {
                Label {
                    Text("Other View", bundle: .module)
                } icon: {
                    Image(systemName: NetworkModules.setting.icon)
                }
            }

            if isMaster {
                Toggle(isOn: battleRoundBinding) {
                    Label {
                        Text("Battle Round", bundle: .module)
                    } icon: {
                        Image(systemName: "shield.lefthalf.filled")
                    }
                }
            }
        } label: {
            Label {
                Text("Sidebar", bundle: .module)
            } icon: {
                Image(systemName: "sidebar.right")
                    .symbolVariant(isSidebarVisible ? .fill : .none)
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
        .imageScale(.large)
        .padding(8)
        .contentShape(.circle)
        .glassEffect(glass, in: .circle)
        .help(
            Text(
                isSidebarVisible ? "Hide Sidebar" : "Show Sidebar",
                bundle: .module
            )
        )
    }

    private var primaryModule: NetworkModules {
        isMaster ? .game : .value
    }

    private var primaryViewTitle: LocalizedStringResource {
        isMaster
            ? LocalizedStringResource("Game View", bundle: .module)
            : LocalizedStringResource("Character View", bundle: .module)
    }

    private var isSidebarVisible: Bool {
        gameScreenModel.isInlineSidebarVisible
    }

    private var sidebarVisibilityBinding: Binding<Bool> {
        Binding(
            get: { isSidebarVisible },
            set: { isVisible in
                setSidebarVisible(isVisible)
            }
        )
    }

    private var primaryViewBinding: Binding<Bool> {
        Binding(
            get: { gameScreenModel.showMainTab == primaryModule },
            set: { isOn in
                setPrimaryView(isOn)
            }
        )
    }

    private var otherViewBinding: Binding<Bool> {
        Binding(
            get: { gameScreenModel.showSettingTab == .setting },
            set: { isOn in
                setOtherView(isOn)
            }
        )
    }

    private var battleRoundBinding: Binding<Bool> {
        Binding(
            get: { gameScreenModel.showsBattleRoundSidebar },
            set: { isOn in
                setBattleRound(isOn)
            }
        )
    }

    private func setSidebarVisible(_ isVisible: Bool) {
        gameScreenModel.showMainTabIOS = isVisible

        if isMaster {
            appSettingsModel.autoShowMasterMainTab = isVisible
        } else {
            appSettingsModel.autoShowPlayerMainTab = isVisible
        }

        withAnimation(accessibilityReduceMotion ? nil : .default) {
            if isVisible {
                showSelectedSidebarView()
            } else {
                gameScreenModel.hideInlineSidebar()
            }
        }
    }

    private func showSelectedSidebarView() {
        if allowsPrimaryView && gameScreenModel.iOSSidebarShowsPrimaryView {
            gameScreenModel.showSettingTab = .none
            gameScreenModel.showMainTab = primaryModule
        } else {
            gameScreenModel.showMainTab = .none
            gameScreenModel.showSettingTab = .setting
        }
    }

    private func setPrimaryView(_ isOn: Bool) {
        guard allowsPrimaryView else { return }
        gameScreenModel.iOSSidebarShowsPrimaryView = isOn
        withAnimation(accessibilityReduceMotion ? nil : .default) {
            gameScreenModel.showMainTab = isOn ? primaryModule : .none
        }
        gameScreenModel.showMainTabIOS = gameScreenModel.isInlineSidebarVisible
    }

    private func setOtherView(_ isOn: Bool) {
        gameScreenModel.iOSSidebarShowsPrimaryView = !isOn
        withAnimation(accessibilityReduceMotion ? nil : .default) {
            gameScreenModel.showSettingTab = isOn ? .setting : .none
        }
        gameScreenModel.showMainTabIOS = gameScreenModel.isInlineSidebarVisible
    }

    private func setBattleRound(_ isOn: Bool) {
        withAnimation(accessibilityReduceMotion ? nil : .default) {
            gameScreenModel.showsBattleRoundSidebar = isOn
        }
        gameScreenModel.showMainTabIOS = gameScreenModel.isInlineSidebarVisible
    }
}

#Preview {
    IOSGameSidebarMenu(isMaster: true, allowsPrimaryView: true)
        .environment(AppSettingsModel())
        .environment(GameScreenModel())
}
#endif
