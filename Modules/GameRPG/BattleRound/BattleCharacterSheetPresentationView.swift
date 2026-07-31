// @copyright André Trettin

import CoreRPG
import MapRPG
import SwiftUI

struct BattleCharacterSheetPresentationView: View {
    let presentation: BattleCharacterSheetPresentation

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SheetRootView(
                root: presentation.root,
                rootModel: presentation.sheet,
                linkTypes: EmptyLinkTransferable.self
            )
            .navigationTitle(Text(verbatim: presentation.name))
            .battleInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        String(localized: "Done", bundle: .module),
                        systemImage: "xmark",
                        action: dismissPresentation
                    )
                }
            }
        }
    }

    private func dismissPresentation() {
        dismiss()
    }
}

#Preview("Battle character sheet", traits: .mockData) {
    let controller = BattleRoundController.preview()

    if let combatant = controller.model.combatants.first(where: { $0.sourceCharacterId != nil }),
       let presentation = BattleCharacterSheetFactory(characterRoot: controller.root.characterRoot).presentation(for: combatant) {
        BattleCharacterSheetPresentationView(presentation: presentation)
            .environment(AppFocusModel())
    }
}
