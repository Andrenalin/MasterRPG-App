// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableGenerationFooterView: View {
    let canConfirm: Bool
    let cancelAction: () -> Void
    let confirmAction: () -> Void

    var body: some View {
        GlassEffectContainerAll {
            HStack {
                GlassButton(action: cancelAction) {
                    Label {
                        Text("Cancel", bundle: .module)
                    } icon: {
                        Image(systemName: "xmark")
                    }
                }

                Spacer()

                GlassButton(isProminent: true, action: confirmAction) {
                    Label {
                        Text("Confirm", bundle: .module)
                    } icon: {
                        Image(systemName: "checkmark")
                    }
                }
                .disabled(!canConfirm)
            }
        }
        .padding()
    }
}

#Preview("Can confirm") {
    TableGenerationFooterView(canConfirm: true, cancelAction: {}, confirmAction: {})
}

#Preview("Cannot confirm") {
    TableGenerationFooterView(canConfirm: false, cancelAction: {}, confirmAction: {})
}
