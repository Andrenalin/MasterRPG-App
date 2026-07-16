// @copyright André Trettin

import SwiftUI

struct GameStatisticsCustomizationSheetView: View {
    @Bindable var model: GameStatisticsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GameStatisticsCustomizationView(model: model)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Label {
                                Text("Done", bundle: .module)
                            } icon: {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
        }
        .presentationSizing(.form)
    }
}

#Preview {
    GameStatisticsCustomizationSheetView(model: .previewFixture())
}
