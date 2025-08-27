// @copyright André Trettin

import SwiftData
import SwiftUI

@MainActor
public struct WeatherRootFactory {
    public static func rootModel(modelContext: ModelContext) -> WeatherRootModel {
        WeatherRootModel(modelContext: modelContext)
    }

    public static func rootView(withoutNavigation: Bool) -> some View {
        WeatherRootView(withoutNavigation: withoutNavigation)
    }
}
