// @copyright André Trettin

import SwiftUI

struct GameStatisticsHighlightCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .bold()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    GameStatisticsHighlightCard(title: "Play Time", value: "42 hr 30 min", systemImage: "clock")
        .padding()
}
