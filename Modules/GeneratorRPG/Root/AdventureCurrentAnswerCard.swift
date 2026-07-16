// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AdventureCurrentAnswerCard: View {
    let text: String

    var body: some View {
        Text(text.markDown())
            .font(.callout)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.thinMaterial, in: .rect(cornerRadius: 8))
    }
}

#Preview {
    AdventureCurrentAnswerCard(text: "The sealed gate opens only when the old oath is spoken.")
        .padding()
}
