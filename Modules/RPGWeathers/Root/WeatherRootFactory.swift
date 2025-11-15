// @copyright André Trettin

import AndrenalinKit
import RPGPhotos
import SwiftData
import SwiftUI

public enum WeatherRootFactory {
    @MainActor public static func root(container: ModelContainer, photoRoot: PhotoRoot) -> WeatherRootModel {
        WeatherRootModel(container: container, photoRoot: photoRoot)
    }

    @MainActor public static func rootView() -> some View {
        WeatherRootView()
    }
    
    @MainActor @ViewBuilder public static func detailView(root: WeatherRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
