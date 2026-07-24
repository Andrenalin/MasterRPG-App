// @copyright André Trettin

import SwiftUI

struct GameStatisticsFilterView: View {
    @Binding var configuration: GameStatisticsDashboardConfiguration

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                GameStatisticsDateRangePicker(configuration: $configuration)
                GameStatisticsGranularityPicker(configuration: $configuration)
                GameStatisticsMetricPicker(configuration: $configuration)
                GameStatisticsDirectionPicker(configuration: $configuration)
            }
            .frame(minWidth: 720)

            Grid(alignment: .leading) {
                GridRow {
                    GameStatisticsDateRangePicker(configuration: $configuration)
                    GameStatisticsGranularityPicker(configuration: $configuration)
                }
                GridRow {
                    GameStatisticsMetricPicker(configuration: $configuration)
                    GameStatisticsDirectionPicker(configuration: $configuration)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pickerStyle(.menu)
    }
}

private struct GameStatisticsDateRangePicker: View {
    @Binding var configuration: GameStatisticsDashboardConfiguration

    var body: some View {
        Picker(selection: $configuration.dateRange) {
            ForEach(GameStatisticsDateRange.allCases) { range in
                Text(range.title).tag(range)
            }
        } label: {
            Text("Date Range", bundle: .module)
        }
    }
}

private struct GameStatisticsGranularityPicker: View {
    @Binding var configuration: GameStatisticsDashboardConfiguration

    var body: some View {
        Picker(selection: $configuration.granularity) {
            ForEach(GameStatisticsGranularity.allCases) { granularity in
                Text(granularity.title).tag(granularity)
            }
        } label: {
            Text("Group By", bundle: .module)
        }
    }
}

private struct GameStatisticsMetricPicker: View {
    @Binding var configuration: GameStatisticsDashboardConfiguration

    var body: some View {
        Picker(selection: $configuration.metric) {
            ForEach(GameStatisticsMetric.allCases) { metric in
                Text(metric.title).tag(metric)
            }
        } label: {
            Text("Metric", bundle: .module)
        }
    }
}

private struct GameStatisticsDirectionPicker: View {
    @Binding var configuration: GameStatisticsDashboardConfiguration

    var body: some View {
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

#Preview {
    @Previewable @State var configuration = GameStatisticsDashboardConfiguration.default
    GameStatisticsFilterView(configuration: $configuration)
}
