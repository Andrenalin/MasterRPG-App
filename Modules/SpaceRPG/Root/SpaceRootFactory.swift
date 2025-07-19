// @copyright André Trettin

import SwiftData
import SwiftUI

@MainActor
public struct SpaceRootFactory {
    public static func rootModel(modelContext: ModelContext) -> SpaceRootModel {
        SpaceRootModel(modelContext: modelContext)
    }

    public static func rootView(withoutNavigation: Bool) -> some View {
        SpaceRootView(withoutNavigation: withoutNavigation)
    }
}
