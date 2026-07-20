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
                    Button("Done", systemImage: "xmark", action: dismissPresentation)
                }
            }
        }
    }

    private func dismissPresentation() {
        dismiss()
    }
}
