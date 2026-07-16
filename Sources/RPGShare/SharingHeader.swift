// @copyright André Trettin

import SwiftUI

struct SharingHeader: View {
    let cancelAction: () -> Void

    var body: some View {
        Button {
            cancelAction()
        } label: {
            Text("Cancel", bundle: .main)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 44)
        
        Text("Add Content to Master RPG", bundle: .main)
            .font(.title3.bold())
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Share extension header") {
    SharingHeader(cancelAction: {})
        .padding()
}
