// @copyright André Trettin

import SwiftUI

struct SharingHeader: View {
    let cancelAction: () -> Void

    var body: some View {
        Button("Cancel") {
            cancelAction()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        
        Text("Add Content to Master RPG")
            .font(.title3.bold())
            .frame(maxWidth: .infinity)
    }
}
