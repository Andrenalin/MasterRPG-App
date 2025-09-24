// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftData
import SwiftUI

@MainActor
public struct WeatherRootFactory {
    public static func rootModel(modelContext: ModelContext, photoRoot: PhotoRootModel) -> WeatherRootModel {
        WeatherRootModel(modelContext: modelContext, photoRoot: photoRoot)
    }

    public static func rootView() -> some View {
        WeatherRootView()
    }
    
    @ViewBuilder
    public static func detailView(root: WeatherRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
