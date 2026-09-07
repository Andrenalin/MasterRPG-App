// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import SwiftUI

struct ExtendedSplitBar: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigator) private var navigator

    private let restoresState: Bool

    @State private var tabSelectedModule: NetworkModules = .map
    
    @State private var column: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar

    init(restoresState: Bool = true) {
        self.restoresState = restoresState
    }
    
    var body: some View {
        ExtendedSplitBarAllCustomTabsView(column: $column, preferredCompactColumn: $preferredCompactColumn)
            .navigationAutoReceive(ExtendedTabRoute.self)
            .focusedSceneValue(\.selectedModule, $tabSelectedModule)
            .applyIf(restoresState) {
                $0.modifier(ExtendedSplitBarRestorationModifier(
                    appModel: appModel,
                    tabSelectedModule: $tabSelectedModule
                ))
            }
    }
}

#Preview {
    ExtendedSplitBar(restoresState: false)
        .environment(AppModel.previewWithoutDatabase)
}

private struct ExtendedSplitBarRestorationModifier: ViewModifier {
    @SceneStorage("ExtendedTabRoute") private var currentModule: ExtendedTabRoute?

    let appModel: AppModel
    @Binding var tabSelectedModule: NetworkModules

    func body(content: Content) -> some View {
        content
            .onChange(of: appModel.selectedExtendedModule) {
                guard appModel.selectedExtendedModule != currentModule else { return }
                currentModule <=> appModel.selectedExtendedModule
            }
            .onChange(of: appModel.selectedModule, initial: true) {
                guard let selectedModule = appModel.selectedModule, selectedModule == .editors, currentModule == nil else { return }
                appModel.selectedExtendedModule <=> .maps
            }
            .onAppear {
                appModel.selectedExtendedModule <=> currentModule
                guard let currentModule else { return }
                tabSelectedModule <=> currentModule.module
            }
    }
}

private extension ExtendedSplitBar {
    func contentView(tab: ExtendedTabRoute) -> some View {
        ManagedPresentationView {
            tab
        }
        .environment(appModel.itemRootController(for: tab.module))
    }
}

private struct ExtendedSplitBarAllCustomTabsView: View {
    @Environment(AppModel.self) private var appModel

    @Binding var column: NavigationSplitViewVisibility
    @Binding var preferredCompactColumn: NavigationSplitViewColumn

    var body: some View {
        ZStack {
            ForEach(ExtendedTabRoute.limitedTabs) { tab in
                let isActive = appModel.selectedExtendedModule == tab
                tabView(tab: tab)
                    .opacity(isActive ? 1 : 0)
                    .allowsHitTesting(isActive)
                    .disabled(!isActive)
                    .accessibilityHidden(!isActive)
            }
        }
#if os(visionOS)
        .ornament(attachmentAnchor: .scene(.trailing), contentAlignment: .leading) {
            SecondaryTabBar()
        }
#endif
    }

    private func tabView(tab: ExtendedTabRoute) -> some View {
        ExtendedSplitWithDetailView(
            tab: tab,
            column: $column,
            preferredCompactColumn: $preferredCompactColumn,
            appModel: appModel
        )
    }
}

#endif
