// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftData
import SwiftUI

public enum WeatherRootFactory {
    @MainActor public static func root(container: ModelContainer, photoRoot: PhotoRootModel) -> WeatherRootModel {
        WeatherRootModel(container: container, photoRoot: photoRoot)
    }

    @MainActor public static func rootView() -> some View {
        WeatherRootView()
    }
    
    @MainActor public static func detailView(root: WeatherRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
