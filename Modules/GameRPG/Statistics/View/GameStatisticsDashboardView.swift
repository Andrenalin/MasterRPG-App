// @copyright André Trettin

import SwiftUI

struct GameStatisticsDashboardView: View {
    @Bindable var model: GameStatisticsModel
    @Bindable var gameCenterModel: GameCenterModel
    let gameCenterController: GameCenterController
    let showsDismissButton: Bool

    init(
        model: GameStatisticsModel,
        gameCenterModel: GameCenterModel,
        gameCenterController: GameCenterController,
        showsDismissButton: Bool = false
    ) {
        self.model = model
        self.gameCenterModel = gameCenterModel
        self.gameCenterController = gameCenterController
        self.showsDismissButton = showsDismissButton
    }

    private let previewSummary = GameStatisticsPreviewController.dashboardPreviewSummary

    var body: some View {
#if os(iOS)
        GameStatisticsIOSDashboardView(
            model: model,
            gameCenterModel: gameCenterModel,
            gameCenterController: gameCenterController,
            previewSummary: previewSummary,
            showsDismissButton: showsDismissButton
        )
#elseif os(tvOS)
        GameStatisticsTVDashboardView(
            model: model,
            gameCenterModel: gameCenterModel,
            gameCenterController: gameCenterController,
            previewSummary: previewSummary
        )
#else
        GameStatisticsPresentedCustomizationDashboardView(
            model: model,
            gameCenterModel: gameCenterModel,
            gameCenterController: gameCenterController,
            previewSummary: previewSummary
        )
#endif
    }
}

#if os(iOS)
private enum GameStatisticsDashboardPage {
    case dashboard
    case customization
}

private struct GameStatisticsIOSDashboardView: View {
    @Bindable var model: GameStatisticsModel
    @Bindable var gameCenterModel: GameCenterModel
    let gameCenterController: GameCenterController
    let previewSummary: GameStatisticsSummary
    let showsDismissButton: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var page: GameStatisticsDashboardPage = .dashboard

    var body: some View {
        Group {
            switch page {
            case .dashboard:
                GameStatisticsDashboardContent(
                    model: model,
                    gameCenterModel: gameCenterModel,
                    gameCenterController: gameCenterController,
                    previewSummary: previewSummary,
                    showsInlineTitle: true
                )
            case .customization:
                GameStatisticsCustomizationView(model: model)
            }
        }
        .navigationTitle(Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    page = page == .dashboard ? .customization : .dashboard
                } label: {
                    Label {
                        if page == .dashboard {
                            Text("Customize", bundle: .module)
                        } else {
                            Text("Dashboard", bundle: .module)
                        }
                    } icon: {
                        if page == .dashboard {
                            Image(systemName: "slider.horizontal.3")
                        } else {
                            Image(systemName: "chart.bar.xaxis")
                        }
                    }
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                if showsDismissButton {
                    Button(
                        String(localized: "Done", bundle: .module),
                        systemImage: "checkmark"
                    ) {
                        dismiss()
                    }
                }
            }
        }
        .modifier(
            GameStatisticsDashboardLifecycleModifier(
                model: model,
                gameCenterModel: gameCenterModel,
                gameCenterController: gameCenterController
            )
        )
    }
}
#endif

#if os(tvOS)
private enum GameStatisticsDashboardDestination: Hashable {
    case customize
}

private struct GameStatisticsTVDashboardView: View {
    @Bindable var model: GameStatisticsModel
    @Bindable var gameCenterModel: GameCenterModel
    let gameCenterController: GameCenterController
    let previewSummary: GameStatisticsSummary

    var body: some View {
        GameStatisticsDashboardContent(
            model: model,
            gameCenterModel: gameCenterModel,
            gameCenterController: gameCenterController,
            previewSummary: previewSummary,
            showsInlineTitle: false
        )
        .navigationTitle(Text("Game Statistics", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: GameStatisticsDashboardDestination.customize) {
                    Label {
                        Text("Customize", bundle: .module)
                    } icon: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
        }
        .navigationDestination(for: GameStatisticsDashboardDestination.self) { destination in
            switch destination {
            case .customize:
                GameStatisticsCustomizationView(model: model)
            }
        }
        .modifier(
            GameStatisticsDashboardLifecycleModifier(
                model: model,
                gameCenterModel: gameCenterModel,
                gameCenterController: gameCenterController
            )
        )
    }
}
#endif

#if os(macOS) || os(visionOS)
private struct GameStatisticsPresentedCustomizationDashboardView: View {
    @Bindable var model: GameStatisticsModel
    @Bindable var gameCenterModel: GameCenterModel
    let gameCenterController: GameCenterController
    let previewSummary: GameStatisticsSummary

    @State private var isCustomizationPresented = false

    var body: some View {
        GameStatisticsDashboardContent(
            model: model,
            gameCenterModel: gameCenterModel,
            gameCenterController: gameCenterController,
            previewSummary: previewSummary,
            showsInlineTitle: false
        )
        .navigationTitle(Text("Game Statistics", bundle: .module))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCustomizationPresented.toggle()
                } label: {
                    Label {
                        Text("Customize", bundle: .module)
                    } icon: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
        }
#if os(macOS)
        .inspector(isPresented: $isCustomizationPresented) {
            GameStatisticsCustomizationInspectorView(model: model)
        }
#else
        .sheet(isPresented: $isCustomizationPresented) {
            GameStatisticsCustomizationSheetView(model: model)
        }
#endif
        .modifier(
            GameStatisticsDashboardLifecycleModifier(
                model: model,
                gameCenterModel: gameCenterModel,
                gameCenterController: gameCenterController
            )
        )
    }
}
#endif

private struct GameStatisticsDashboardLifecycleModifier: ViewModifier {
    @Bindable var model: GameStatisticsModel
    @Bindable var gameCenterModel: GameCenterModel
    let gameCenterController: GameCenterController

    private var authenticationRequest: Binding<GameCenterAuthenticationRequest?> {
        Binding(
            get: { gameCenterModel.authenticationRequest },
            set: { request in
                if request == nil {
                    gameCenterModel.dismissAuthentication()
                }
            }
        )
    }

    func body(content: Content) -> some View {
        content
#if os(tvOS)
            // The Game Center sign-in is a full screen on the TV (code entry / QR).
            .fullScreenCover(item: authenticationRequest) { request in
                GameCenterAuthenticationView(request: request)
                    .ignoresSafeArea()
            }
#else
            .sheet(item: authenticationRequest) { request in
                GameCenterAuthenticationView(request: request)
            }
#endif
            .onAppear {
                gameCenterController.setAccessPoint(active: true)
            }
            .onDisappear {
                gameCenterController.setAccessPoint(active: false)
            }
    }
}

private struct GameStatisticsDashboardContent: View {
    @Bindable var model: GameStatisticsModel
    @Bindable var gameCenterModel: GameCenterModel
    let gameCenterController: GameCenterController
    let previewSummary: GameStatisticsSummary
    let showsInlineTitle: Bool

    var body: some View {
        ScrollView {
            LazyVStack {
                if showsInlineTitle {
                    Text("Game Statistics", bundle: .module)
                        .font(.largeTitle)
                        .bold()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

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
            .frame(maxWidth: .infinity)
            .frame(maxWidth: 1_200)
            .padding()
        }
        .refreshable {
            await model.repair()
        }
        .task(id: model.configuration) {
            await model.reload()
        }
    }
}

#Preview {
    let gameCenterModel = GameCenterModel()
    NavigationStack {
        GameStatisticsDashboardView(
            model: .previewFixture(),
            gameCenterModel: gameCenterModel,
            gameCenterController: GameCenterController(model: gameCenterModel),
            showsDismissButton: true
        )
    }
}
