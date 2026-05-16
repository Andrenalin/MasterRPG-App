// @copyright André Trettin

import SwiftUI

/// Picker subview — @Bindable on the concrete ListDisplayModel registers @Observable tracking.
struct LinkItemPickerView: View {
    @Bindable var listDisplayModel: ListDisplayModel

    var body: some View {
        Picker(selection: $listDisplayModel.listMode) {
            ForEach(ListDisplayModel.ListMode.allCases) { mode in
                Text(mode.title, bundle: .module)
                    .tag(mode)
            }
        } label: {
            Text("List Mode", bundle: .module)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
}
