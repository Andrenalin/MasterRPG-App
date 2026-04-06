// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

public enum WeatherRootFactory {
    @MainActor public static func root(tagController: TagController, photoRoot: PhotoRootModel) -> WeatherRootModel {
        WeatherRootModel(tagController: tagController, photoRoot: photoRoot)
    }

    @MainActor public static func rootView() -> some View {
        WeatherRootView()
    }
    
    @MainActor public static func detailView(root: WeatherRootModel) -> some View {
        ItemSplitDetailRouteRootView(root: root.rootController, route: WeatherRoute.detail(root.navigationModel.selectedItemId ?? UUID()))
    }
}
