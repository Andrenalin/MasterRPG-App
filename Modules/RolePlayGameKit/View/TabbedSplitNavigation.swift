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

    @State private var contentColumnWidth: Double = 350
    @State private var fallbackNavigationModel = ModuleNavigationModel()

    var body: some View {
        @Bindable var appModel = appModel
        let controller = appModel.itemRootController(for: selectedModule)
        @Bindable var model = controller?.navigationModel ?? fallbackNavigationModel
        let canShow = appNavigationModel.canShowInspector(appSizeModel: appWindowSizeModel)
        let inspectorBinding = Binding(
            get: { canShow && model.showInspector },
            set: { if canShow { model.showInspector = $0 } }
        )

        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
            TabSidebar(restoresState: restoresState)
                .navigationSplitViewColumnWidth(min: 96, ideal: 140, max: 180)
        } content: {
            ManagedPresentationView {
                appModel.selectedModule
            }
            .environment(appModel.itemRootController(for: selectedModule))
            .navigationSplitViewColumnWidth(min: 250, ideal: contentColumnWidth, max: 600)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .global).width
            } action: { newWidth in
                contentColumnWidth = newWidth
            }
        } detail: {
            SplitDetailView(isExtendedRoutes: false)
                .environment(appModel.itemRootController(for: selectedModule))
        }
        .inspectorAll(isPresented: inspectorBinding) {
            if canShow && model.showInspector {
                AppInspectorView(isExtendedRoutes: false)
            }
        }
        .onChange(of: appModel.selectedModule) {
            guard let selected = appModel.selectedModule, appModel.menuSelectedModule != selected.module else { return }
            appModel.menuSelectedModule = selected.module
        }
        .focusedSceneValue(\.selectedModule, $appModel.menuSelectedModule)
        .onNavigationReceive(assign: $appModel.selectedModule)
        .navigationSplitViewStyle(.prominentDetail)
        .applyIf(restoresState && rolePlayStateRestorationEnabled) {
            $0.modifier(TabbedSplitNavigationRestorationModifier(
                contentColumnWidth: $contentColumnWidth
            ))
        }
    }
    
    var selectedModule: NetworkModules {
        (appModel.selectedModule ?? .game).module
    }
}

#Preview {
    let appModel = AppModel.previewWithoutDatabase

    TabbedSplitNavigation(restoresState: false)
        .environment(appModel)
        .environment(appModel.appNavigationModel)
        .environment(AppWindowSizeModel())
}

private struct TabbedSplitNavigationRestorationModifier: ViewModifier {
    @AppStorage("contentColumnWidth") private var storedContentColumnWidth: Double = 350

    @Binding var contentColumnWidth: Double

    func body(content: Content) -> some View {
        content
            .onChange(of: storedContentColumnWidth, initial: true) {
                contentColumnWidth <=> storedContentColumnWidth
            }
            .onChange(of: contentColumnWidth) {
                storedContentColumnWidth <=> contentColumnWidth
            }
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
