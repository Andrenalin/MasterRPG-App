// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableGenerationHeaderView: View {
    let model: TableGenerationModel
    let controller: TableGenerationController

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(model.root.tableName)
                    .font(.title)
                    .bold()
                // Hidden once a first choice has been made, to give the
                // occurrence list more room.
                if model.currentOutcome == nil {
                    Text("Choose the results for each generated table.", bundle: .module)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                withAnimation {
                    controller.autoRoll(model: model)
                }
            } label: {
                Image(systemName: "dice.fill")
            }
            .selectedRoundButton(
                title: String(localized: "Auto Roll", bundle: .module),
                module: .table,
                isSelected: false
            )
            // Once every table is fully decided there's nothing left to
            // roll — re-enabled automatically the moment a selection change
            // makes a new choice available again (`isFullyDecided` goes
            // back to `false`).
            .disabled(model.root.entries.isEmpty || model.isFullyDecided)
        }
        .padding()
    }
}

#Preview("Dice table", traits: .mockData) {
    TableGenerationHeaderView(model: .preview, controller: .preview)
}

#Preview("Empty table", traits: .mockData) {
    TableGenerationHeaderView(model: .previewEmpty, controller: .preview)
}

#Preview("First entry selected", traits: .mockData) {
    TableGenerationHeaderView(model: .previewResolved, controller: .preview)
}
