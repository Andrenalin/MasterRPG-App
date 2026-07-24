// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TabSidebar: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.rolePlayStateRestorationEnabled) private var rolePlayStateRestorationEnabled

    private let restoresState: Bool

    init(restoresState: Bool = true) {
        self.restoresState = restoresState
    }

    var body: some View {
        @Bindable var appModel = appModel
        List(selection: $appModel.selectedModule) {
            allTabs
        }
        .themedListSurface()
        .applyIf(restoresState && rolePlayStateRestorationEnabled) {
            $0.modifier(TabSidebarRestorationModifier(appModel: appModel))
        }
    }

    @ViewBuilder var allTabs: some View {
        Section {
            tabView(tab: .adventures)
            tabView(tab: .values)
            tabView(tab: .maps)
            tabView(tab: .weathers)
        } header: {
            Text("Library", bundle: .module)
        }

        Section {
            tabView(tab: .rules)
            tabView(tab: .pdfs)
            tabView(tab: .tables)
        } header: {
            Text("References", bundle: .module)
        }

        Section {
            tabView(tab: .audios)
            tabView(tab: .dice)
            tabView(tab: .photos)
            tabView(tab: .space)
        } header: {
            Text("Material", bundle: .module)
        }
    }

    @ViewBuilder func tabView(tab: RootRoute) -> some View {
        NavigationLink(to: tab) {
            ModuleTabLabel(route: tab)
        }
        .moduleListItemTint(tab.module)
        .tag(tab)
    }
}

#Preview("Library sidebar") {
    TabSidebar(restoresState: false)
        .environment(AppModel.previewWithoutDatabase)
}

private struct TabSidebarRestorationModifier: ViewModifier {
    @SceneStorage("RootRoute") private var storedTab: RootRoute = .adventures

    let appModel: AppModel

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard storedTab != appModel.selectedModule else { return }
                appModel.selectedModule = storedTab
            }
            .onChange(of: appModel.selectedModule) {
                guard storedTab != appModel.selectedModule, let selectedModule = appModel.selectedModule else { return }
                storedTab = selectedModule
            }
    }
}
