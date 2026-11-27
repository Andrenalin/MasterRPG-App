// @copyright André Trettin

import CoreRPG
import Foundation

// The dashboard configuration types, split out of GameStatisticsTypes.swift. See CODE_AUDIT_29 §9.9.

enum GameStatisticsDateRange: Int, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case lastThirtyDays
    case lastSixMonths
    case lastYear
    case allTime

    var id: Self { self }

    var title: String {
        switch self {
        case .lastThirtyDays: String(localized: "30 Days", bundle: .module)
        case .lastSixMonths: String(localized: "6 Months", bundle: .module)
        case .lastYear: String(localized: "1 Year", bundle: .module)
        case .allTime: String(localized: "All Time", bundle: .module)
        }
    }

    func interval(endingAt end: Date, calendar: Calendar) -> DateInterval? {
        let start: Date?
        switch self {
        case .lastThirtyDays:
            start = calendar.date(byAdding: .day, value: -30, to: end)
        case .lastSixMonths:
            start = calendar.date(byAdding: .month, value: -6, to: end)
        case .lastYear:
            start = calendar.date(byAdding: .year, value: -1, to: end)
        case .allTime:
            return nil
        }
        return start.map { DateInterval(start: $0, end: end) }
    }
}

enum GameStatisticsGranularity: Int, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case day
    case week
    case month

    var id: Self { self }

    var title: String {
        switch self {
        case .day: String(localized: "Day", bundle: .module)
        case .week: String(localized: "Week", bundle: .module)
        case .month: String(localized: "Month", bundle: .module)
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }
}

enum GameStatisticsMetric: Int, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case duration
    case sessions

    var id: Self { self }

    var title: String {
        switch self {
        case .duration: String(localized: "Play Time", bundle: .module)
        case .sessions: String(localized: "Games", bundle: .module)
        }
    }
}

enum GameStatisticsSection: Int, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case activity
    case schedule
    case roles
    case characters
    case adventures
    case dice
    case sharedContent
    case party
    case network

    var id: Self { self }

    var title: String {
        switch self {
        case .activity: String(localized: "Activity", bundle: .module)
        case .schedule: String(localized: "When You Play", bundle: .module)
        case .roles: String(localized: "Roles", bundle: .module)
        case .characters: String(localized: "Characters", bundle: .module)
        case .adventures: String(localized: "Adventures", bundle: .module)
        case .dice: String(localized: "Dice", bundle: .module)
        case .sharedContent: String(localized: "Shared Content", bundle: .module)
        case .party: String(localized: "Party", bundle: .module)
        case .network: String(localized: "Connection", bundle: .module)
        }
    }

    var systemImage: String {
        switch self {
        case .activity: "chart.xyaxis.line"
        case .schedule: "calendar"
        case .roles: "person.badge.key"
        case .characters: "person.crop.circle"
        case .adventures: "book.pages"
        case .dice: "dice"
        case .sharedContent: "square.and.arrow.up"
        case .party: "person.3"
        case .network: "network"
        }
    }
}

struct GameStatisticsDashboardConfiguration: Codable, Hashable, Sendable {
    var dateRange: GameStatisticsDateRange = .lastSixMonths
    var granularity: GameStatisticsGranularity = .week
    var metric: GameStatisticsMetric = .duration
    var direction: GameStatisticDirection? = nil
    var sectionOrder: [GameStatisticsSection] = GameStatisticsSection.allCases
    var hiddenSections: Set<GameStatisticsSection> = []

    static let `default` = GameStatisticsDashboardConfiguration()

    /// The fields the loaded data depends on. The dashboard reloads when this changes, not when
    /// a section is reordered, hidden or the metric switched. See CODE_AUDIT_28 §7.4.
    struct DataKey: Hashable, Sendable {
        let dateRange: GameStatisticsDateRange
        let granularity: GameStatisticsGranularity
        let direction: GameStatisticDirection?
    }

    var dataKey: DataKey {
        DataKey(dateRange: dateRange, granularity: granularity, direction: direction)
    }

    private enum CodingKeys: String, CodingKey {
        case dateRange, granularity, metric, direction, sectionOrder, hiddenSections
    }

    /// Tolerant of older and newer saved data: a missing field keeps its default, an unknown case
    /// is dropped, and a section the saved order does not know is appended. A dashboard saved by a
    /// newer version must not reset the whole configuration. See CODE_AUDIT_26 §5.86.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = GameStatisticsDashboardConfiguration()
        dateRange = (try? container.decodeIfPresent(GameStatisticsDateRange.self, forKey: .dateRange)) ?? defaults.dateRange
        granularity = (try? container.decodeIfPresent(GameStatisticsGranularity.self, forKey: .granularity)) ?? defaults.granularity
        metric = (try? container.decodeIfPresent(GameStatisticsMetric.self, forKey: .metric)) ?? defaults.metric
        direction = (try? container.decodeIfPresent(GameStatisticDirection.self, forKey: .direction)) ?? nil
        let savedOrder = ((try? container.decodeIfPresent([Int].self, forKey: .sectionOrder)) ?? nil) ?? []
        var order: [GameStatisticsSection] = []
        for raw in savedOrder {
            if let section = GameStatisticsSection(rawValue: raw), !order.contains(section) {
                order.append(section)
            }
        }
        order += GameStatisticsSection.allCases.filter { !order.contains($0) }
        sectionOrder = order
        let savedHidden = ((try? container.decodeIfPresent([Int].self, forKey: .hiddenSections)) ?? nil) ?? []
        hiddenSections = Set(savedHidden.compactMap(GameStatisticsSection.init(rawValue:)))
    }

    init(
        dateRange: GameStatisticsDateRange = .lastSixMonths,
        granularity: GameStatisticsGranularity = .week,
        metric: GameStatisticsMetric = .duration,
        direction: GameStatisticDirection? = nil,
        sectionOrder: [GameStatisticsSection] = GameStatisticsSection.allCases,
        hiddenSections: Set<GameStatisticsSection> = []
    ) {
        self.dateRange = dateRange
        self.granularity = granularity
        self.metric = metric
        self.direction = direction
        self.sectionOrder = sectionOrder
        self.hiddenSections = hiddenSections
    }

    var visibleSections: [GameStatisticsSection] {
        sectionOrder.filter { !hiddenSections.contains($0) }
    }

    /// What the dashboard shows when the selected range holds no game. A range narrower than
    /// "All Time" may simply miss the games that exist, so it says so and keeps the filters
    /// reachable; only "All Time" without a game is a dashboard that has nothing yet (the sample).
    /// See CODE_AUDIT_26 §5.19.
    var emptyState: GameStatisticsEmptyState {
        dateRange == .allTime ? .sample : .noGamesInRange
    }
}

enum GameStatisticsEmptyState: Sendable {
    /// No game was ever recorded: the sample dashboard explains what the statistics will show.
    case sample
    /// No game in a limited range; a wider range may have some.
    case noGamesInRange
}
