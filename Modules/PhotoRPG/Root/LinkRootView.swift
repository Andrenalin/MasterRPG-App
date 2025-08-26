// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct LinkRootView: View {
    let isInspector: Bool

    @Environment(PhotoRootModel.self) private var root
    
    var body: some View {
        CoreRPG.LinkRootView(root: root, isInspector: isInspector)
    }
}

#Preview(traits: .mockData) {
    LinkRootView(isInspector: false)
}
