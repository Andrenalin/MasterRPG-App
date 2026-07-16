// @copyright André Trettin

import SwiftUI

struct DetailSelectionEditorView: View {
    let root: AdventureRootModel
    let model: AdventureModel

    var body: some View {
        DiceDropSection(root: root, model: model)
        PhotoDropSection(root: root, model: model)
    }
}

#Preview(traits: .mockData) {
    DetailSelectionEditorView(root: .preview, model: .preview)
}
