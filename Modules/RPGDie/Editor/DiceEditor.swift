// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct DiceEditor: View {
    let editController: EditController
    
    @Environment(DiceRoot.self) private var root
    
    var body: some View {
        Section {
            LabeledContent {
                diceView
            } label: {
                Text("Dice", bundle: .module)
            }

            LabeledContent {
                DiceBag { die in
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

private extension DiceEditor {
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
    DiceEditor(editController: .preview)
        .environment(DiceRoot.preview)
}
