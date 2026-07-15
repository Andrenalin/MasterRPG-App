// @copyright André Trettin

import Foundation

struct GameStatisticsExportController: Sendable {
    func text(from summary: GameStatisticsSummary, generatedAt: Date = .now) -> String {
        var lines = [
            String(localized: "MasterRPG Game Statistics", bundle: .module),
            generatedAt.formatted(date: .long, time: .shortened),
            "",
            "\(String(localized: "Games", bundle: .module)): \(summary.sessionCount.formatted())",
            "\(String(localized: "Play Time", bundle: .module)): \(GameStatisticsFormat.duration(summary.totalDuration))",
            "\(String(localized: "Average", bundle: .module)): \(GameStatisticsFormat.duration(summary.averageDuration))",
            "\(String(localized: "Longest Game", bundle: .module)): \(GameStatisticsFormat.duration(summary.longestDuration))",
            "\(String(localized: "Game Master", bundle: .module)): \(GameStatisticsFormat.duration(summary.gameMasterDuration))",
            "\(String(localized: "Player", bundle: .module)): \(GameStatisticsFormat.duration(summary.playerDuration))",
            "\(String(localized: "Dice Rolls", bundle: .module)): \(summary.diceRollCount.formatted())",
            "\(String(localized: "Criticals", bundle: .module)): \(summary.criticalCount.formatted())",
            "\(String(localized: "Fumbles", bundle: .module)): \(summary.fumbleCount.formatted())"
        ]

        append(points: summary.characters, title: String(localized: "Characters", bundle: .module), to: &lines)
        append(points: summary.adventures, title: String(localized: "Adventures", bundle: .module), to: &lines)
        append(points: summary.modules, title: String(localized: "Shared Content", bundle: .module), to: &lines, usesDuration: false)
        return lines.joined(separator: "\n")
    }

    private func append(
        points: [GameStatisticCategoryPoint],
        title: String,
        to lines: inout [String],
        usesDuration: Bool = true
    ) {
        guard !points.isEmpty else { return }
        lines.append("")
        lines.append(title)
        for point in points {
            let value = usesDuration ? GameStatisticsFormat.duration(point.value) : point.count.formatted()
            lines.append("• \(point.title): \(value)")
        }
    }
}
