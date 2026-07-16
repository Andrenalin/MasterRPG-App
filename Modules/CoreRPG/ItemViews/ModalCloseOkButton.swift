// @copyright André Trettin

import SwiftUI

struct ModalCloseOkButton: View {
    let dismissAction: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            withAnimation {
                if let dismissAction {
                    dismissAction()
                } else {
                    dismiss()
                }
            }
        } label: {
            Label {
                Text("Ok", bundle: .module)
            } icon: {
                Image(systemName: "checkmark.circle")
            }
        }
    }
}

#Preview("OK") {
    ModalCloseOkButton(dismissAction: {})
}
