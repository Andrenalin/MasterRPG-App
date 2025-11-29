// @copyright André Trettin

import SwiftUI

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

struct ModalPresentCloseButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            withAnimation { isPresented = false }
        } label: {
            Label {
                Text("Close", bundle: .module)
            } icon: {
                Image(systemName: "xmark.circle")
            }
        }
    }
}

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
