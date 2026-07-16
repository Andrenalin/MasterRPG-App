// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailSelectionEditorView: View {
    let root: CharacterRootModel
    let model: ValueModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        DiceDropSection(root: root, model: model)
        PhotoDropSection(root: root, model: model)
    }
}

#Preview(traits: .mockData) {
    DetailSelectionEditorView(root: .preview, model: .preview)
}
