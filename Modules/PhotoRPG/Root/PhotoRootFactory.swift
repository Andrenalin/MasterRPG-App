// @copyright André Trettin

import SwiftData
import SwiftUI

@MainActor
public struct PhotoRootFactory {
    public static func rootModel(modelContext: ModelContext) -> PhotoRootModel {
        PhotoRootModel(modelContext: modelContext)
    }

    public static func rootView(withoutNavigation: Bool) -> some View {
        PhotoRootView(withoutNavigation: withoutNavigation)
        
    }
}
