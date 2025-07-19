// @copyright André Trettin

import RolePlayGameKit

import PhotoRPG
import SpaceRPG

import SwiftUI
import SwiftData

struct AppRootView: View {
    var body: some View {
        TabNavigation()
    }
}


#Preview {
    AppRootView()
        .modelContainer(for: [PhotoDataModel.self, PhotoEntryDataModel.self, SpaceDataModel.self, SpaceEntryDataModel.self], inMemory: true)
        .environment(AppModel())
}
