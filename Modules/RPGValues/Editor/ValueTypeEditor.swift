// @copyright André Trettin

import AndrenalinKit
import RPGDie
import SwiftUI

struct ValueTypeEditor: View {
    let editController: EditController
    let model: ValueModel
    let entryId: UUID

    var body: some View {
        let _ = Self._printChanges()
        @Bindable var model = model
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
