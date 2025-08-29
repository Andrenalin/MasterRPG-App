// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct SelectionRootView: View {
    @Environment(PhotoRootModel.self) private var root
    
    var body: some View {
        CoreRPG.LinkRootView(root: root, type: .selection)
    }
}

#Preview(traits: .mockData) {

    #if os(macOS)
    ManagedNavigationStack {
        SelectionRootView()
    }
    #else
    ZStack {
        Color.red
            .sheet(isPresented: .constant(true)) {
                ManagedNavigationStack {
                    SelectionRootView()
                }
            }
            .ignoresSafeArea()
    }
    #endif
}
