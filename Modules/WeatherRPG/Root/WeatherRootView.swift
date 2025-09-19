// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct WeatherRootView: View {
    let withoutNavigation: Bool

    @Environment(WeatherRootModel.self) private var root

    var body: some View {
        let _ = Self._printChanges()
        
        ItemRootView(root: root.rootController, withoutNavigation: withoutNavigation) {
            DetailRootView(selectedId: nil)
        }
        .overlay {
            SaveView(root: root)
        }
        .navigationAutoReceive(WeatherRoute.self)
    }
}

struct SaveView: View {
    let root: WeatherRootModel
    
    @SceneStorage("WeatherRoute") private var route: ItemRootRoute?
    @SceneStorage("WeatherDisplayModel") private var displayMode: ListDisplayModel.DisplayMode = .medium
    @SceneStorage("WeatherListModel") private var listMode: ListDisplayModel.ListMode = .list

    var body: some View {
        let _ = Self._printChanges()

        Color.clear
            .applyItemRootRoute(listControllable: root.listControllable, route: $route)
            .syncListDisplay(listControllable: root.listControllable, displayMode: $displayMode, listMode: $listMode)
    }
}

#Preview("Embed", traits: .mockData) {
    ManagedNavigationStack {
        WeatherRootView(withoutNavigation: true)
    }
}

#Preview("Split", traits: .mockData) {
    WeatherRootView(withoutNavigation: false)
}

