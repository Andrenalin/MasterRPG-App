// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TabbedSplitNavigation: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AppWindowSizeModel.self) private var appWindowSizeModel
    @Environment(AppNavigationModel.self) private var appNavigationModel
    @Environment(\.rolePlayStateRestorationEnabled) private var rolePlayStateRestorationEnabled

    private let restoresState: Bool

    init(restoresState: Bool = true) {
        self.restoresState = restoresState
    }

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    @AppStorage(TabbedSplitContentColumnWidth.storageKey)
    private var storedContentColumnWidth = TabbedSplitContentColumnWidth.defaultWidth
    @State private var transientContentColumnWidth = TabbedSplitContentColumnWidth.defaultWidth
    @State private var fallbackNavigationModel = ModuleNavigationModel()
    @FocusState private var navigationColumnFocus: NavigationColumnFocus?

    var body: some View {
        @Bindable var appModel = appModel
        let controller = appModel.itemRootController(for: selectedModule)
        @Bindable var model = controller?.navigationModel ?? fallbackNavigationModel
        let canShow = appNavigationModel.canShowInspector(appSizeModel: appWindowSizeModel)
        let inspectorBinding = Binding(
            get: { canShow && model.showInspector },
            set: { if canShow { model.showInspector = $0 } }
        )
        let restoresContentColumnWidth = restoresState && rolePlayStateRestorationEnabled
        let contentColumnWidth = TabbedSplitContentColumnWidth.normalized(
            restoresContentColumnWidth
                ? storedContentColumnWidth
                : transientContentColumnWidth
        )

        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
            TabSidebar(restoresState: restoresState)
                .navigationSplitViewColumnWidth(min: 96, ideal: 140, max: 180)
        } content: {
            ManagedPresentationView {
                appModel.selectedModule
            }
            .environment(appModel.itemRootController(for: selectedModule))
            .navigationSplitViewColumnWidth(
                min: TabbedSplitContentColumnWidth.minimumWidth,
                ideal: contentColumnWidth,
                max: TabbedSplitContentColumnWidth.maximumWidth
            )
            .onGeometryChange(for: Double.self) { proxy in
                Double(proxy.size.width)
            } action: { newWidth in
                updateContentColumnWidth(
                    measuredWidth: newWidth,
                    restoresWidth: restoresContentColumnWidth
                )
            }
        } detail: {
            SplitDetailView(module: selectedModule)
                .environment(appModel.itemRootController(for: selectedModule))
        }
        .inspectorAll(isPresented: inspectorBinding) {
            if canShow && model.showInspector {
                AppInspectorView(module: selectedModule)
            }
        }
        .onChange(of: appModel.selectedModule) {
            guard let selected = appModel.selectedModule, appModel.menuSelectedModule != selected.module else { return }
            appModel.menuSelectedModule = selected.module
        }
        .focusedSceneValue(\.selectedModule, $appModel.menuSelectedModule)
        .onNavigationReceive(assign: $appModel.selectedModule)
        .navigationSplitViewStyle(.prominentDetail)
        .environment(\.navigationColumnFocus, $navigationColumnFocus)
    }
    
    var selectedModule: NetworkModules {
        (appModel.selectedModule ?? .game).module
    }

    private func updateContentColumnWidth(
        measuredWidth: Double,
        restoresWidth: Bool
    ) {
        let currentWidth = restoresWidth
            ? storedContentColumnWidth
            : transientContentColumnWidth
        guard let updatedWidth = TabbedSplitContentColumnWidth.updatedWidth(
            measuredWidth: measuredWidth,
            currentWidth: currentWidth
        ) else { return }

        if restoresWidth {
            storedContentColumnWidth = updatedWidth
        } else {
            transientContentColumnWidth = updatedWidth
        }
    }
}

#Preview {
    let appModel = AppModel.previewWithoutDatabase

    TabbedSplitNavigation(restoresState: false)
        .environment(appModel)
        .environment(appModel.appNavigationModel)
        .environment(AppWindowSizeModel())
}

enum TabbedSplitContentColumnWidth {
    static let storageKey = "contentColumnWidth"
    static let minimumWidth = 250.0
    static let defaultWidth = 350.0
    static let maximumWidth = 600.0

    static func normalized(_ width: Double) -> Double {
        guard width.isFinite else { return defaultWidth }
        return min(max(width, minimumWidth), maximumWidth)
    }

    static func updatedWidth(
        measuredWidth: Double,
        currentWidth: Double
    ) -> Double? {
        guard measuredWidth.isFinite, measuredWidth > 0 else { return nil }
        let normalizedMeasurement = normalized(measuredWidth)
        let normalizedCurrentWidth = normalized(currentWidth)
        guard abs(normalizedMeasurement - normalizedCurrentWidth) >= 0.5 else {
            return nil
        }
        return normalizedMeasurement
    }
}

private struct RolePlayStateRestorationEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var rolePlayStateRestorationEnabled: Bool {
        get { self[RolePlayStateRestorationEnabledKey.self] }
        set { self[RolePlayStateRestorationEnabledKey.self] = newValue }
    }
}

extension View {
    func rolePlayStateRestorationEnabled(_ enabled: Bool) -> some View {
        environment(\.rolePlayStateRestorationEnabled, enabled)
    }
}
