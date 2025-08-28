// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct SelectionRootView: View {
    @Environment(PhotoRootModel.self) private var root
    
    var body: some View {
        CoreRPG.LinkRootView(root: root, type: .singleSelection)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(PhotoRootModel.self) var root
    
    ManagedNavigationStack {
        SelectionRootView()
    }
}
