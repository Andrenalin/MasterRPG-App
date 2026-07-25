// @copyright André Trettin

import SwiftUI

struct BattleRoundHeader: View {
    let isRunning: Bool
    let hasEntries: Bool
    let round: Int
    let activeAttackerName: String?
    let initiativeOrder: BattleInitiativeOrder
    let actions: BattleRoundActions
    @Binding var isConfigurationExpanded: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                BattleRoundHeading(
                    isRunning: isRunning,
                    round: round,
                    activeAttackerName: activeAttackerName
                )
                Spacer(minLength: 8)
                BattleInitiativeOrderMenu(
                    selection: initiativeOrderBinding,
                    isDisabled: isRunning && !hasEntries
                )
                configurationButton
                BattleRoundHeaderActions(isRunning: isRunning, actions: actions)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    BattleRoundHeading(
                        isRunning: isRunning,
                        round: round,
                        activeAttackerName: activeAttackerName
                    )
                    Spacer(minLength: 4)
                    BattleInitiativeOrderMenu(
                        selection: initiativeOrderBinding,
                        isDisabled: isRunning && !hasEntries
                    )
                    configurationButton
                }
                BattleRoundHeaderActions(isRunning: isRunning, actions: actions)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
#if os(tvOS)
        .background(.black.opacity(0.35))
#else
        .background(.bar)
#endif
    }

    private var configurationButton: some View {
        Button(
            String(localized: "Battle Settings", bundle: .module),
            systemImage: "slider.horizontal.3"
        ) {
            isConfigurationExpanded.toggle()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .accessibilityValue(
            isConfigurationExpanded
                ? Text("Expanded", bundle: .module)
                : Text("Collapsed", bundle: .module)
        )
    }

    private var initiativeOrderBinding: Binding<BattleInitiativeOrder> {
        Binding(
            get: { initiativeOrder },
            set: { newOrder in
                actions.setInitiativeOrder(newOrder)
            }
        )
    }
}

#Preview("Battle header") {
    @Previewable @State var isConfigurationExpanded = false
    let model = BattleRoundPreviewData.model()

    BattleRoundHeader(
        isRunning: model.isRunning,
        hasEntries: !model.entries.isEmpty,
        round: model.roundCounter,
        activeAttackerName: model.activeEntry.flatMap { model.attacker(for: $0) }?.name,
        initiativeOrder: model.initiativeOrder,
        actions: .preview(model: model),
        isConfigurationExpanded: $isConfigurationExpanded
    )
    .frame(width: 760)
}

#Preview("Compact battle header") {
    @Previewable @State var isConfigurationExpanded = false
    let model = BattleRoundPreviewData.model()

    BattleRoundHeader(
        isRunning: model.isRunning,
        hasEntries: !model.entries.isEmpty,
        round: model.roundCounter,
        activeAttackerName: model.activeEntry.flatMap { model.attacker(for: $0) }?.name,
        initiativeOrder: model.initiativeOrder,
        actions: .preview(model: model),
        isConfigurationExpanded: $isConfigurationExpanded
    )
    .frame(width: 360)
}
