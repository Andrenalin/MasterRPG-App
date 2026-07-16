// @copyright André Trettin

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
    private let previewSummary = GameStatisticsPreviewController().summary(
        referenceDate: GamePreviewData.referenceDate,
        calendar: GamePreviewData.calendar
    )

    var body: some View {
        ScrollView {
            LazyVStack {
                GameCenterStatusView(model: gameCenterModel, controller: gameCenterController)

                if let errorMessage = model.errorMessage {
                    ContentUnavailableView {
                        Label {
                            Text("Statistics Unavailable", bundle: .module)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                    } description: {
                        Text(errorMessage)
                    }
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
                Button {
                    isCustomizationPresented.toggle()
                } label: {
                    Label {
                        Text("Customize", bundle: .module)
                    } icon: {
                        Image(systemName: "slider.horizontal.3")
                    }
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

#Preview {
    let gameCenterModel = GameCenterModel()
    NavigationStack {
        GameStatisticsDashboardView(
            model: .previewFixture(),
            gameCenterModel: gameCenterModel,
            gameCenterController: GameCenterController(model: gameCenterModel)
        )
    }
}
