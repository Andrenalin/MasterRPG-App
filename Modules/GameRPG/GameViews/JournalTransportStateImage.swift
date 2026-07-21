// @copyright André Trettin

import CoreRPG
import SwiftUI

struct JournalTransportStateImage: View {
    let state: SharePlayJournalTransportState

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        switch state {
        case .pending:
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Adding to journal", bundle: .module))
        case .succeeded:
            Image(systemName: "checkmark")
                .foregroundStyle(.tint)
                .accessibilityLabel(Text("Added to journal", bundle: .module))
        case .failed:
            Image(systemName: "xmark")
                .foregroundStyle(.red)
                .accessibilityLabel(Text("Failed to add to journal", bundle: .module))
        }
    }
}

#Preview {
    JournalTransportStateImage(state: .succeeded)
}
