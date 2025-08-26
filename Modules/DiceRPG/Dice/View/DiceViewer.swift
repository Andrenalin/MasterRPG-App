// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DiceViewer: View {
    let model: DiceConfigDataModel
    let isEditor: Bool
    
    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(model.dice) { die in
                    Button {
                        if isEditor {
                            withAnimation { root.editController.remove(die: die, from: model) }
                        } else {
                            
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
    @Previewable @Query var models: [DiceConfigDataModel]

    DiceViewer(model: models.first!, isEditor: true)
}
