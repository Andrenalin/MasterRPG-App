// @copyright André Trettin

import SwiftUI

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

#Preview("Presented close") {
    @Previewable @State var isPresented = true
    ModalPresentCloseButton(isPresented: $isPresented)
}
