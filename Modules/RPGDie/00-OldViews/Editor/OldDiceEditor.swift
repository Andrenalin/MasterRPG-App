// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct OldDiceEditor: View {
    let editController: EditController
    
    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        Section {
            LabeledContent {
                diceView
            } label: {
                Text("Dice", bundle: .module)
            }

            LabeledContent {
                OldDiceBag { die in
                    Task { await editController.add(die: die) }
                }
            } label: {
                Text("Add", bundle: .module)
            }
        } header: {
#if os(macOS)
            Divider()
                .padding(.top)
#endif
            Text("Dice Editor", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
}

private extension OldDiceEditor {
    var diceView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(editController.model.entries) { die in
                    Button {
                        Task { await editController.remove(die: die) }
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            DieViewerView(gameController: root.gameController, diceId: UUID(), die: die, withoutResult: true, resultColor: [])
                                .padding(4)
                            
                            Image(systemName: "x.circle.fill")
                                .offset(x: -8, y: 4)
                        }
                    }
                    .borderLessTVBottonStyle()
                }
            }
        }
    }
}

#Preview {
    OldDiceEditor(editController: .preview)
        .environment(DiceRootModel.preview)
}
