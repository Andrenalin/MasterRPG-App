// @copyright André Trettin

import SwiftUI

struct GameStatisticsNoChartDataView: View {
    var body: some View {
        Label {
            Text("No data for this selection", bundle: .module)
        } icon: {
            Image(systemName: "chart.bar.xaxis")
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

#Preview {
    GameStatisticsNoChartDataView()
}
