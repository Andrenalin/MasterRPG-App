// @copyright André Trettin

#if os(iOS)
import CoreRPG
import SwiftUI

struct IOSGameSidebarMenu: View {
    let isMaster: Bool
    let allowsPrimaryView: Bool

    @Environment(AppSettingsModel.self) private var appSettingsModel
    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        let glass: Glass = if isSidebarVisible {
            .regular.tint(NetworkModules.game.tint.opacity(0.7)).interactive()
        } else {
            .regular.interactive()
        }

        Menu {
            GameTableMenuToggle()

            Divider()

            Toggle(isOn: sidebarVisibilityBinding) {
                Label {
                    Text("Sidebar", bundle: .module)
                } icon: {
                    Image(systemName: "sidebar.right")
                }
            }

            Toggle(isOn: primaryViewBinding) {
                Label {
                    Text(verbatim: currentSidebarViewTitle)
                } icon: {
                    Image(systemName: currentSidebarViewIcon)
                }
            }
            .disabled(!isSidebarVisible || !allowsPrimaryView)

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

    private var isSidebarVisible: Bool {
        gameScreenModel.showMainTab != .none || gameScreenModel.showSettingTab != .none
    }

    private var isShowingPrimaryView: Bool {
        if gameScreenModel.showMainTab != .none {
            return true
        }
        if gameScreenModel.showSettingTab != .none {
            return false
        }
        return allowsPrimaryView && gameScreenModel.iOSSidebarShowsPrimaryView
    }

    private var currentSidebarViewTitle: String {
        if isShowingPrimaryView {
            return isMaster
                ? String(localized: "Game View", bundle: .module)
                : String(localized: "Character View", bundle: .module)
        }
        return String(localized: "Other View", bundle: .module)
    }

    private var currentSidebarViewIcon: String {
        isShowingPrimaryView ? primaryModule.icon : NetworkModules.setting.icon
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
            get: { isShowingPrimaryView },
            set: { showsPrimaryView in
                setPrimaryViewVisible(showsPrimaryView)
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
                gameScreenModel.showMainTab = .none
                gameScreenModel.showSettingTab = .none
            }
        }
    }

    private func setPrimaryViewVisible(_ showsPrimaryView: Bool) {
        guard allowsPrimaryView else { return }
        gameScreenModel.iOSSidebarShowsPrimaryView = showsPrimaryView
        guard isSidebarVisible else { return }
        withAnimation(accessibilityReduceMotion ? nil : .default) {
            showSelectedSidebarView()
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
}

#Preview {
    IOSGameSidebarMenu(isMaster: true, allowsPrimaryView: true)
        .environment(AppSettingsModel())
        .environment(GameScreenModel())
}
#endif
