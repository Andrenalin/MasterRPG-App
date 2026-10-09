// @copyright André Trettin

import MapRPG
import SwiftUI

struct BattleRoundHeader: View {
    let isRunning: Bool
    let round: Int
    let activeAttackerName: String?
    let initiativeOrder: BattleInitiativeOrder
    let controller: BattleRoundController
    @Binding var isConfigurationExpanded: Bool

    var body: some View {
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
                    BattleRoundHeaderActions(controller: controller)
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
                    Spacer(minLength: 4)
                }
                if isRunning {
                    BattleRoundHeaderActions(controller: controller)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 16)
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
        initiativeOrder: model.initiativeOrder,
        controller: controller,
        isConfigurationExpanded: $isConfigurationExpanded
    )
}
