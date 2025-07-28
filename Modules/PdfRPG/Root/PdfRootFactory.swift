// @copyright André Trettin

import SwiftData
import SwiftUI

@MainActor
public struct PdfRootFactory {
    public static func rootModel(modelContext: ModelContext) -> PdfRootModel {
        PdfRootModel(modelContext: modelContext)
    }

    public static func rootView(withoutNavigation: Bool) -> some View {
        PdfRootView(withoutNavigation: withoutNavigation)
        
    }
}
