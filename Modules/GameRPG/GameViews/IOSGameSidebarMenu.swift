// @copyright André Trettin

#if os(iOS)
import CoreRPG
import SwiftUI

struct IOSGameSidebarMenu: View {
    let isMaster: Bool
    let allowsPrimaryView: Bool
    /// Whether the menu also holds the view switches. The regular width shows them as buttons
    /// below the menu button instead (`IOSGameSidebarViewButtons`).
    var showsViewToggles: Bool = true
    /// Whether the menu offers the single / horizontal / vertical sidebar layouts (the game
    /// master on iPad).
    var showsLayoutOptions: Bool = false
    /// Whether the menu offers the trailing / bottom sidebar placements (the iPhone).
    var showsPlacementOptions: Bool = false

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
                    gameScreenModel.toggleSidebarSize()
                }
            } label: {
                Label {
                    Text(
                        gameScreenModel.isSidebarEnlarged ? "Reduce Sidebar" : "Enlarge Sidebar",
                        bundle: .module
                    )
                } icon: {
                    Image(
                        systemName: gameScreenModel.isSidebarEnlarged
                            ? "square.resize.down"
                            : "square.resize.up"
                    )
                }
            }
            .disabled(!isSidebarVisible)

            if showsPlacementOptions {
                Divider()

                ForEach(GameSidebarPlacement.allCases) { placement in
                    Toggle(isOn: placementBinding(for: placement)) {
                        Label {
                            Text(placement.title)
                        } icon: {
                            Image(systemName: placement.systemImage)
                        }
                    }
                }
            }

            if showsLayoutOptions {
                Divider()

                ForEach(GameSidebarLayout.allCases) { layout in
                    Toggle(isOn: layoutBinding(for: layout)) {
                        Label {
                            Text(layout.title)
                        } icon: {
                            Image(systemName: layout.systemImage)
                        }
                    }
                }
            }

            if showsViewToggles {
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

    /// Only one layout is on at a time: turning the active one off keeps it on.
    private func layoutBinding(for layout: GameSidebarLayout) -> Binding<Bool> {
        Binding(
            get: { gameScreenModel.sidebarLayout == layout },
            set: { isOn in
                guard isOn else { return }
                setLayout(layout)
            }
        )
    }

    /// Only one placement is on at a time: turning the active one off keeps it on.
    private func placementBinding(for placement: GameSidebarPlacement) -> Binding<Bool> {
        Binding(
            get: { gameScreenModel.sidebarPlacement == placement },
            set: { isOn in
                guard isOn else { return }
                setPlacement(placement)
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

    private func setPlacement(_ placement: GameSidebarPlacement) {
        if isMaster {
            appSettingsModel.masterSidebarPlacement = placement.rawValue
        } else {
            appSettingsModel.playerSidebarPlacement = placement.rawValue
        }
        withAnimation(accessibilityReduceMotion ? nil : .default) {
            gameScreenModel.sidebarPlacement = placement
        }
    }

    private func setLayout(_ layout: GameSidebarLayout) {
        appSettingsModel.masterSidebarLayout = layout.rawValue
        withAnimation(accessibilityReduceMotion ? nil : .default) {
            gameScreenModel.sidebarLayout = layout
        }
    }

    private func showSelectedSidebarView() {
        if gameScreenModel.isSplitSidebar {
            gameScreenModel.showMainTab = primaryModule
        } else if allowsPrimaryView && gameScreenModel.iOSSidebarShowsPrimaryView {
            gameScreenModel.showSettingTab = .none
            gameScreenModel.showMainTab = primaryModule
        } else {
            gameScreenModel.showMainTab = .none
            gameScreenModel.showSettingTab = .setting
        }
    }

    private func setPrimaryView(_ isOn: Bool) {
        withAnimation(accessibilityReduceMotion ? nil : .default) {
            gameScreenModel.setSidebarPrimaryView(
                isOn,
                primaryModule: primaryModule,
                allowsPrimaryView: allowsPrimaryView
            )
        }
    }

    private func setOtherView(_ isOn: Bool) {
        withAnimation(accessibilityReduceMotion ? nil : .default) {
            gameScreenModel.setSidebarOtherView(isOn)
        }
    }

    private func setBattleRound(_ isOn: Bool) {
        withAnimation(accessibilityReduceMotion ? nil : .default) {
            gameScreenModel.setSidebarBattleRound(isOn)
        }
    }
}

#Preview {
    IOSGameSidebarMenu(isMaster: true, allowsPrimaryView: true)
        .environment(AppSettingsModel())
        .environment(GameScreenModel())
}
#endif
