// @copyright André Trettin

#if os(iOS) || os(macOS)
import SwiftUI

struct GameStatisticsCustomizationInspectorView: View {
    @Bindable var model: GameStatisticsModel
#if os(iOS)
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    var body: some View {
#if os(iOS)
        NavigationStack {
            GameStatisticsCustomizationView(model: model)
                .toolbar {
                    if horizontalSizeClass == .compact {
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
        }
        .presentationSizing(.form)
        .inspectorColumnWidth(min: 340, ideal: 400, max: 480)
#else
        GameStatisticsCustomizationView(model: model)
            .inspectorColumnWidth(min: 340, ideal: 400, max: 480)
#endif
    }
}

#Preview {
    GameStatisticsCustomizationInspectorView(model: .previewFixture())
}
#endif
