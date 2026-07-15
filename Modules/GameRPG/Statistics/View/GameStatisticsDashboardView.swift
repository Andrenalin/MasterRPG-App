// @copyright André Trettin

import Charts
import SwiftUI

#if os(tvOS)
private enum GameStatisticsDashboardDestination: Hashable {
    case customize
}
#endif

struct GameStatisticsDashboardView: View {
    @Bindable var model: GameStatisticsModel
    @Bindable var gameCenterModel: GameCenterModel
    let gameCenterController: GameCenterController
#if !os(tvOS)
    @State private var isCustomizationPresented = false
#endif
    private let previewSummary = GameStatisticsPreviewController().summary()

    var body: some View {
        ScrollView {
            LazyVStack {
                GameCenterStatusView(
                    model: gameCenterModel,
                    controller: gameCenterController
                )

                if let errorMessage = model.errorMessage {
                    ContentUnavailableView(
                        "Statistics Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if model.isLoading, model.summary.sessionCount == 0 {
                    ProgressView {
                        Text("Loading Statistics", bundle: .module)
                    }
                        .controlSize(.large)
                } else if model.summary.sessionCount == 0 {
                    GameStatisticsPreviewDashboardView(
                        summary: previewSummary,
                        collectionEnabled: model.isCollectionEnabled
                    )
                } else {
                    GameStatisticsFilterView(configuration: $model.configuration)
                    GameStatisticsHighlightsView(summary: model.summary)

                    ForEach(model.configuration.visibleSections) { section in
                        GameStatisticsSectionView(
                            section: section,
                            summary: model.summary,
                            metric: model.configuration.metric
                        )
                    }

                    GameStatisticsRecentSessionsView(
                        sessions: model.summary.recentSessions,
                        model: model
                    )
                }
            }
            .padding()
        }
        .navigationTitle(Text("Game Statistics", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
#if os(tvOS)
                NavigationLink(value: GameStatisticsDashboardDestination.customize) {
                    Label {
                        Text("Customize", bundle: .module)
                    } icon: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
#else
                Button("Customize", systemImage: "slider.horizontal.3") {
                    isCustomizationPresented.toggle()
                }
#endif
            }
        }
#if os(iOS) || os(macOS)
        .inspector(isPresented: $isCustomizationPresented) {
            GameStatisticsCustomizationInspectorView(model: model)
        }
#elseif os(visionOS)
        .sheet(isPresented: $isCustomizationPresented) {
            GameStatisticsCustomizationSheetView(model: model)
        }
#elseif os(tvOS)
        .navigationDestination(for: GameStatisticsDashboardDestination.self) { destination in
            switch destination {
            case .customize:
                GameStatisticsCustomizationView(model: model)
            }
        }
#endif
        .sheet(
            item: Binding(
                get: { gameCenterModel.authenticationRequest },
                set: { request in
                    if request == nil {
                        gameCenterModel.dismissAuthentication()
                    }
                }
            )
        ) { request in
            GameCenterAuthenticationView(request: request)
        }
        .refreshable {
            await model.reload()
        }
        .task(id: model.configuration) {
            await model.reload()
        }
        .onAppear {
            gameCenterController.setAccessPoint(active: true)
        }
        .onDisappear {
            gameCenterController.setAccessPoint(active: false)
        }
    }
}

private struct GameCenterStatusView: View {
    @Bindable var model: GameCenterModel
    let controller: GameCenterController

    var body: some View {
        HStack {
            Image(systemName: model.isAuthenticated ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.questionmark")
                .imageScale(.large)
                .foregroundStyle(model.isAuthenticated ? .green : .secondary)
            VStack(alignment: .leading) {
                Text("Game Center", bundle: .module)
                    .bold()
                if model.isAuthenticated {
                    Text(model.playerName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Sign in to earn achievements.", bundle: .module)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.isReportingAchievements {
                ProgressView()
            } else if !model.isAuthenticated {
                Button("Sign In", systemImage: "gamecontroller") {
                    controller.authenticate()
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

private struct GameStatisticsFilterView: View {
    @Binding var configuration: GameStatisticsDashboardConfiguration

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                Picker("Date Range", selection: $configuration.dateRange) {
                    ForEach(GameStatisticsDateRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }

                Picker("Group By", selection: $configuration.granularity) {
                    ForEach(GameStatisticsGranularity.allCases) { granularity in
                        Text(granularity.title).tag(granularity)
                    }
                }

                Picker("Metric", selection: $configuration.metric) {
                    ForEach(GameStatisticsMetric.allCases) { metric in
                        Text(metric.title).tag(metric)
                    }
                }

                Picker("Direction", selection: $configuration.direction) {
                    Text("Sent and Received", bundle: .module).tag(GameStatisticDirection?.none)
                    ForEach([GameStatisticDirection.incoming, .outgoing]) { direction in
                        Text(direction.title).tag(Optional(direction))
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .pickerStyle(.menu)
    }
}

private struct GameStatisticsPreviewDashboardView: View {
    private let previewSections: [GameStatisticsSection] = [
        .activity, .characters, .dice, .sharedContent
    ]
    private let additionalSections: [GameStatisticsSection] = [
        .schedule, .roles, .adventures, .party, .network
    ]

    let summary: GameStatisticsSummary
    let collectionEnabled: Bool

    var body: some View {
        VStack {
            GameStatisticsPreviewHeader(collectionEnabled: collectionEnabled)
            GameStatisticsHighlightsView(summary: summary)

            ForEach(previewSections) { section in
                GameStatisticsSectionView(section: section, summary: summary, metric: .duration)
            }

            GameStatisticsPreviewSessionsView(sessions: summary.recentSessions)

            GameStatisticsChartCard(
                title: String(localized: "More Insights", bundle: .module),
                systemImage: "sparkles"
            ) {
                Text("Completed games can also reveal these patterns.", bundle: .module)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))]) {
                    ForEach(additionalSections) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.quaternary, in: .rect(cornerRadius: 14))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct GameStatisticsPreviewHeader: View {
    let collectionEnabled: Bool

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Label {
                    Text("Your Adventures, Visualized", bundle: .module)
                } icon: {
                    Image(systemName: "sparkles.rectangle.stack")
                }
                .font(.title2)
                .bold()

                Spacer()

                Text("Example", bundle: .module)
                    .textCase(.uppercase)
                    .font(.caption)
                    .bold()
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(.blue, in: .capsule)
                    .foregroundStyle(.white)
            }

            Text("This sample dashboard shows what MasterRPG can discover from activity during your games. Example data is never saved or reported to Game Center.", bundle: .module)
                .foregroundStyle(.secondary)

            if collectionEnabled {
                Label {
                    Text("Finish your first game to replace this preview with your own story.", bundle: .module)
                } icon: {
                    Image(systemName: "flag.checkered")
                }
            } else {
                Label {
                    Text("Turn on collection in Customize to build your personal dashboard.", bundle: .module)
                } icon: {
                    Image(systemName: "chart.bar.doc.horizontal")
                }
                .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.blue.opacity(0.12), in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

private struct GameStatisticsHighlightsView: View {
    let summary: GameStatisticsSummary

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))]) {
            GameStatisticsHighlightCard(
                title: String(localized: "Games", bundle: .module),
                value: summary.sessionCount.formatted(),
                systemImage: "person.3"
            )
            GameStatisticsHighlightCard(
                title: String(localized: "Play Time", bundle: .module),
                value: GameStatisticsFormat.duration(summary.totalDuration),
                systemImage: "clock"
            )
            GameStatisticsHighlightCard(
                title: String(localized: "Average", bundle: .module),
                value: GameStatisticsFormat.duration(summary.averageDuration),
                systemImage: "chart.bar"
            )
            GameStatisticsHighlightCard(
                title: String(localized: "Longest Game", bundle: .module),
                value: GameStatisticsFormat.duration(summary.longestDuration),
                systemImage: "trophy"
            )
            GameStatisticsHighlightCard(
                title: String(localized: "Dice Rolls", bundle: .module),
                value: summary.diceRollCount.formatted(),
                systemImage: "dice"
            )
            GameStatisticsHighlightCard(
                title: String(localized: "Criticals", bundle: .module),
                value: summary.criticalCount.formatted(),
                systemImage: "sparkles"
            )
        }
    }
}

private struct GameStatisticsHighlightCard: View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

private struct GameStatisticsSectionView: View {
    let section: GameStatisticsSection
    let summary: GameStatisticsSummary
    let metric: GameStatisticsMetric

    var body: some View {
        switch section {
        case .activity:
            GameStatisticsActivityChart(points: summary.activity, metric: metric)
        case .schedule:
            GameStatisticsScheduleChart(points: summary.schedule)
        case .roles:
            GameStatisticsCategoryBarChart(section: section, points: summary.roles, metric: metric)
        case .characters:
            GameStatisticsCategoryBarChart(section: section, points: summary.characters, metric: metric)
        case .adventures:
            GameStatisticsCategoryBarChart(section: section, points: summary.adventures, metric: metric)
        case .dice:
            GameStatisticsDiceChart(points: summary.diceOutcomes)
        case .sharedContent:
            GameStatisticsCountBarChart(section: section, points: summary.modules)
        case .party:
            GameStatisticsCategoryBarChart(section: section, points: summary.party, metric: metric)
        case .network:
            GameStatisticsNetworkChart(points: summary.network, byteCount: summary.payloadByteCount)
        }
    }
}

private struct GameStatisticsRecentSessionsView: View {
    let sessions: [GameStatisticSessionSnapshot]
    @Bindable var model: GameStatisticsModel

    var body: some View {
        GameStatisticsChartCard(
            title: String(localized: "Recent Games", bundle: .module),
            systemImage: "clock.arrow.circlepath"
        ) {
            LazyVStack {
                ForEach(sessions) { session in
                    NavigationLink {
                        GameStatisticsSessionDetailView(session: session, model: model)
                    } label: {
                        GameStatisticsSessionRow(session: session)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }
}

private struct GameStatisticsPreviewSessionsView: View {
    let sessions: [GameStatisticSessionSnapshot]

    var body: some View {
        GameStatisticsChartCard(
            title: String(localized: "Example Games", bundle: .module),
            systemImage: "clock.arrow.circlepath"
        ) {
            LazyVStack {
                ForEach(sessions) { session in
                    GameStatisticsSessionRow(session: session, showsDisclosureIndicator: false)
                    Divider()
                }
            }
        }
    }
}

private struct GameStatisticsSessionRow: View {
    let session: GameStatisticSessionSnapshot
    let showsDisclosureIndicator: Bool

    init(session: GameStatisticSessionSnapshot, showsDisclosureIndicator: Bool = true) {
        self.session = session
        self.showsDisclosureIndicator = showsDisclosureIndicator
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(session.adventureTitle.isEmpty ? session.role.title : session.adventureTitle)
                    .bold()
                Text(session.startedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(GameStatisticsFormat.duration(session.duration))
                .foregroundStyle(.secondary)
            if showsDisclosureIndicator {
                Image(systemName: "chevron.forward")
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

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
