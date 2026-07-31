// @copyright André Trettin

import CoreRPG
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
    let root = MapRootModel.previewFixture()
    let model = BattleRoundPreviewData.model()

    if let combatant = model.combatants.first(where: { $0.sourceCharacterId != nil }),
       let presentation = BattleCharacterSheetFactory(root: root).presentation(for: combatant) {
        BattleCharacterSheetPresentationView(presentation: presentation)
            .environment(AppFocusModel())
    }
}
