// @copyright André Trettin

import MapRPG
import SwiftUI

struct BattleRoundHeader: View {
    let isRunning: Bool
    let round: Int
    let activeAttackerName: String?
    let controller: BattleRoundController
    @Binding var isConfigurationExpanded: Bool
    /// "End" asks before it ends the battle; the screen presents the dialog.
    let requestEnd: @MainActor () -> Void

    var body: some View {
#if os(macOS)
        // On macOS the turn actions are window toolbar items
        // (`BattleRoundWindowToolbar`), where window-level actions belong.
        // The header keeps the settings button and the round.
        HStack(spacing: BattleRoundSpacing.loose) {
            BattleRoundConfigurationButton(isExpanded: $isConfigurationExpanded)
            BattleRoundHeading(
                isRunning: isRunning,
                round: round,
                activeAttackerName: activeAttackerName
            )
            Spacer(minLength: BattleRoundSpacing.standard)
        }
        .battleRoundHeaderChrome()
#else
        ViewThatFits(in: .horizontal) {
            HStack(spacing: BattleRoundSpacing.loose) {
                BattleRoundConfigurationButton(isExpanded: $isConfigurationExpanded)
                BattleRoundHeading(
                    isRunning: isRunning,
                    round: round,
                    activeAttackerName: activeAttackerName
                )
                Spacer(minLength: BattleRoundSpacing.standard)
                if isRunning {
                    BattleRoundHeaderActions(controller: controller, requestEnd: requestEnd)
                }
            }

            VStack(alignment: .leading, spacing: BattleRoundSpacing.standard) {
                HStack(spacing: BattleRoundSpacing.standard) {
                    BattleRoundConfigurationButton(isExpanded: $isConfigurationExpanded)
                    BattleRoundHeading(
                        isRunning: isRunning,
                        round: round,
                        activeAttackerName: activeAttackerName
                    )
                    Spacer(minLength: BattleRoundSpacing.tight)
                }
                if isRunning {
                    BattleRoundHeaderActions(controller: controller, requestEnd: requestEnd)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .battleRoundHeaderChrome()
#endif
    }
}

private extension View {
    func battleRoundHeaderChrome() -> some View {
        padding(.horizontal, BattleRoundSpacing.wide)
        .padding(.vertical, BattleRoundSpacing.loose)
        .overlay(alignment: .bottom) {
            Divider()
        }
#if os(tvOS)
        .background(.black.opacity(0.35))
#endif
    }
}

private struct BattleRoundConfigurationButton: View {
    @Binding var isExpanded: Bool

    var body: some View {
        Button(
            String(localized: "Battle Settings", bundle: .module),
            systemImage: "slider.horizontal.3"
        ) {
            isExpanded.toggle()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .accessibilityValue(
            isExpanded
                ? Text("Expanded", bundle: .module)
                : Text("Collapsed", bundle: .module)
        )
    }
}

#Preview("Compact battle header") {
    @Previewable @State var isConfigurationExpanded = false
    let controller = BattleRoundController.preview()
    let model = controller.model

    BattleRoundHeader(
        isRunning: model.isRunning,
        round: model.roundCounter,
        activeAttackerName: model.activeEntry.flatMap { model.attacker(for: $0) }?.name,
        controller: controller,
        isConfigurationExpanded: $isConfigurationExpanded,
        requestEnd: {}
    )
}
