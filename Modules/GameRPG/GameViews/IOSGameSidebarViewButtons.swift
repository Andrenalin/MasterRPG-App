// @copyright André Trettin

#if os(iOS)
import CoreRPG
import SwiftUI

/// The sidebar view switches (primary view, other view, game master only battle round) as a
/// button column for the regular width (iPad). It hangs below the sidebar menu button and moves
/// with it when the sidebar opens.
struct IOSGameSidebarViewButtons: View {
    let isMaster: Bool
    let allowsPrimaryView: Bool

    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        VStack(spacing: GameScreenModel.mapOverlaySpacing) {
            IOSGameSidebarViewButton(
                title: primaryViewTitle,
                systemImage: primaryModule.icon,
                tintModule: primaryModule,
                isOn: primaryViewBinding
            )
            .disabled(!allowsPrimaryView)

            IOSGameSidebarViewButton(
                title: LocalizedStringResource("Other View", bundle: .module),
                systemImage: NetworkModules.setting.icon,
                tintModule: .setting,
                isOn: otherViewBinding
            )

            if isMaster {
                IOSGameSidebarViewButton(
                    title: LocalizedStringResource("Battle Round", bundle: .module),
                    systemImage: "shield.lefthalf.filled",
                    tintModule: .game,
                    isOn: battleRoundBinding
                )
            }
        }
    }

    private var primaryModule: NetworkModules {
        isMaster ? .game : .value
    }

    private var primaryViewTitle: LocalizedStringResource {
        isMaster
            ? LocalizedStringResource("Game View", bundle: .module)
            : LocalizedStringResource("Character View", bundle: .module)
    }

    private var primaryViewBinding: Binding<Bool> {
        Binding(
            get: { gameScreenModel.showMainTab == primaryModule },
            set: { isOn in
                withAnimation(accessibilityReduceMotion ? nil : .default) {
                    gameScreenModel.setSidebarPrimaryView(
                        isOn,
                        primaryModule: primaryModule,
                        allowsPrimaryView: allowsPrimaryView
                    )
                }
            }
        )
    }

    private var otherViewBinding: Binding<Bool> {
        Binding(
            get: { gameScreenModel.showSettingTab == .setting },
            set: { isOn in
                withAnimation(accessibilityReduceMotion ? nil : .default) {
                    gameScreenModel.setSidebarOtherView(isOn)
                }
            }
        )
    }

    private var battleRoundBinding: Binding<Bool> {
        Binding(
            get: { gameScreenModel.showsBattleRoundSidebar },
            set: { isOn in
                withAnimation(accessibilityReduceMotion ? nil : .default) {
                    gameScreenModel.setSidebarBattleRound(isOn)
                }
            }
        )
    }
}

/// One round glass toggle button, styled like the sidebar menu button above it.
private struct IOSGameSidebarViewButton: View {
    let title: LocalizedStringResource
    let systemImage: String
    let tintModule: NetworkModules
    @Binding var isOn: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        let glass: Glass = if isOn {
            .regular.tint(theme.tint(for: tintModule).opacity(0.7)).interactive()
        } else {
            .regular.interactive()
        }

        Button {
            isOn.toggle()
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .symbolVariant(isOn ? .fill : .none)
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
        .imageScale(.large)
        .padding(8)
        .contentShape(.circle)
        .glassEffect(glass, in: .circle)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .help(Text(title))
    }
}

#Preview {
    IOSGameSidebarViewButtons(isMaster: true, allowsPrimaryView: true)
        .environment(GameScreenModel())
}
#endif
