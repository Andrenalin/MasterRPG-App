// @copyright André Trettin

import PhotoRPG
import SwiftData
import SwiftUI

@MainActor
public struct WeatherRootFactory {
    public static func rootModel(modelContext: ModelContext, photoRoot: PhotoRootModel) -> WeatherRootModel {
        WeatherRootModel(modelContext: modelContext, photoRoot: photoRoot)
    }

    public static func rootView(withoutNavigation: Bool) -> some View {
        WeatherRootView(withoutNavigation: withoutNavigation)
    }
}
