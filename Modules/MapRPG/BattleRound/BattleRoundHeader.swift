// @copyright André Trettin

import SwiftUI

struct BattleRoundHeader: View {
    let isRunning: Bool
    let hasEntries: Bool
    let round: Int
    let activeAttackerName: String?
    let initiativeOrder: BattleInitiativeOrder
    let actions: BattleRoundActions

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

    private var initiativeOrderBinding: Binding<BattleInitiativeOrder> {
        Binding(
            get: { initiativeOrder },
            set: { newOrder in
                actions.setInitiativeOrder(newOrder)
            }
        )
    }
}
