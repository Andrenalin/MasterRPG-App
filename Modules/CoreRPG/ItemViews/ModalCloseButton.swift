// @copyright André Trettin

import SwiftUI

#Preview("Close") {
    ModalCloseButton(dismissAction: {})
}

struct ModalCloseButton: View {
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
                Text("Close", bundle: .module)
            } icon: {
                Image(systemName: "xmark.circle")
            }
        }
    }
}
