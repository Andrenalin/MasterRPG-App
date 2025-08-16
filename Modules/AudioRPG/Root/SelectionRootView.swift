// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftData
import SwiftUI

struct SelectionRootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var listModel = ListModel()
    @State private var cacheItemListModel = CacheItemListModel()

    var body: some View {
        ManagedNavigationStack { navigator in
            SelectionListView()
                .navigationDestination(for: DetailRoute.self) { route in
                    route
                }
        }
        .environment(listModel)
        .environment(cacheItemListModel)
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        SelectionRootView()
    }
}
