// @copyright André Trettin

import SwiftData
import SwiftUI

@MainActor
public struct AudioRootFactory {
    public static func rootModel(modelContext: ModelContext) -> AudioRootModel {
        AudioRootModel(modelContext: modelContext)
    }

    public static func rootView(withoutNavigation: Bool) -> some View {
        AudioRootView(withoutNavigation: withoutNavigation)
    }
}
