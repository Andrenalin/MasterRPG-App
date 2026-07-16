// @copyright André Trettin

import SwiftUI

struct GameStatisticsSelectionLabel: View {
    let title: String
    let value: String

    var body: some View {
        VStack {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .bold()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.thickMaterial, in: .rect(cornerRadius: 10))
    }
}

#Preview {
    GameStatisticsSelectionLabel(title: "Jul 15, 2026", value: "4 hr 15 min")
}
