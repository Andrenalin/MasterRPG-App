// @copyright André Trettin

import SwiftUI

struct GameStatisticsFilterView: View {
    @Binding var configuration: GameStatisticsDashboardConfiguration

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                Picker(selection: $configuration.dateRange) {
                    ForEach(GameStatisticsDateRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                } label: {
                    Text("Date Range", bundle: .module)
                }

                Picker(selection: $configuration.granularity) {
                    ForEach(GameStatisticsGranularity.allCases) { granularity in
                        Text(granularity.title).tag(granularity)
                    }
                } label: {
                    Text("Group By", bundle: .module)
                }

                Picker(selection: $configuration.metric) {
                    ForEach(GameStatisticsMetric.allCases) { metric in
                        Text(metric.title).tag(metric)
                    }
                } label: {
                    Text("Metric", bundle: .module)
                }

                Picker(selection: $configuration.direction) {
                    Text("Sent and Received", bundle: .module).tag(GameStatisticDirection?.none)
                    ForEach([GameStatisticDirection.incoming, .outgoing]) { direction in
                        Text(direction.title).tag(Optional(direction))
                    }
                } label: {
                    Text("Direction", bundle: .module)
                }
            }
        }
        .scrollIndicators(.hidden)
        .pickerStyle(.menu)
    }
}

#Preview {
    @Previewable @State var configuration = GameStatisticsDashboardConfiguration.default
    GameStatisticsFilterView(configuration: $configuration)
}
