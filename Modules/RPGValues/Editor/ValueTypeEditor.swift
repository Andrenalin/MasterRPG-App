// @copyright André Trettin

import AndrenalinKit
import RPGDie
import SwiftUI

struct ValueTypeEditor: View {
    let editController: EditController
    let entryId: UUID

    var body: some View {
        @Bindable var model = editController.model
        LabeledContent {
            Picker(selection: $model[entryId].type) {
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
}
