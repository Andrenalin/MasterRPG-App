// @copyright André Trettin

import SwiftUI

struct GameStatisticsChartCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading) {
            Label(title, systemImage: systemImage)
                .font(.title3)
                .bold()
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
    }
}

#Preview {
    GameStatisticsChartCard(title: "Activity", systemImage: "chart.xyaxis.line") {
        Text(verbatim: "12 games across 42 hours")
            .foregroundStyle(.secondary)
    }
    .padding()
}
