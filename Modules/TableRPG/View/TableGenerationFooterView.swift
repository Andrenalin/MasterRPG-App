// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableGenerationFooterView: View {
    let closeAction: () -> Void

    var body: some View {
        HStack {
            Button(action: closeAction) {
                Image(systemName: "xmark")
            }
            .selectedRoundButton(
                title: String(localized: "Close", bundle: .module),
                module: .table,
                isSelected: false
            )

            Spacer()
        }
        .padding()
    }
}

#Preview {
    TableGenerationFooterView(closeAction: {})
}
