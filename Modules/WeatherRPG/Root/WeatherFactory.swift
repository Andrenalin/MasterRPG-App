// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

public enum WeatherFactory {
    @MainActor public static func root(tagController: TagController, photoRoot: PhotoRootModel) -> WeatherRootModel {
        WeatherRootModel(tagController: tagController, photoRoot: photoRoot)
    }

    @MainActor public static func rootView() -> some View {
        WeatherRootView()
    }
    
    @MainActor @ViewBuilder public static func detailView(root: WeatherRootModel) -> some View {
        if let itemId = root.navigationModel.selectedItemId {
            ManagedNavigationStack(name: "Split-Weather") {
                ItemSplitDetailRouteRootView(root: root.rootController, route: WeatherRoute.detail(itemId))
            }
        } else {
            SplitContentUnavailableView(module: root.configurable.module)
        }
    }
}
