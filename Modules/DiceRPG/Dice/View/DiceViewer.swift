// @copyright André Trettin

import AndrenalinKit
import SwiftData
import SwiftUI

struct DiceViewer: View {
    let model: DiceModel
    let isEditor: Bool
    
    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(model.dice) { die in
                    Button {
                        if isEditor {
                            withAnimation { root.editController.remove(die: die) }
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            ThumbnailDice(die: die)
                                .padding(4)
                            
                            if isEditor {
                                Image(systemName: "x.circle.fill")
                                    .tint(.red)
                                    .offset(x: -8, y: 4)
                            }
                        }
                    }
                    .borderLessTVBottonStyle()
                }
            }
        }
    }
}


#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root

    DiceViewer(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]), isEditor: true)
}
