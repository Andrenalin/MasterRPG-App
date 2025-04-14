// @copyright André Trettin

import AndrenalinKit
import RPGDie
import SwiftUI

struct ValueTypeEditor: View {
    let editController: EditController
    let entryId: UUID

    var body: some View {
        LabeledContent {
            Picker(selection: selection) {
                ForEach(ValueEntryModel.ValueType.allCases) { option in
                    Text(option.title)
                        .tag(option)
                }
            } label: {
                Text("value Type", bundle: .module)
            }
            .labelsHidden()
            .pickerStyle(.automatic)
            .tint(Color.accentColor)
        } label: {
            Text("Type", bundle: .module)
        }
    }

    private var selection: Binding<ValueEntryModel.ValueType> {
        Binding {
            editController.model[entryId].type
        } set: {
            editController.reset(entryId: entryId, type: $0)
        }
    }
}
