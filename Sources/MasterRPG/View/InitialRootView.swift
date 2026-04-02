// @copyright André Trettin

import CoreRPG
import RolePlayGameKit
import SwiftUI

// MARK: - View State

enum AppInitialState: Codable, Equatable, Hashable {
    case initializing
    case ready
}

extension AppInitialState: NavigationDestination {
    var body: some View {
        switch self {
        case .initializing:
            DatabaseInitializationView()
        case .ready:
            DestinationReadyView()
        }
    }
}

struct InitialRootView: View {
    let appModel: AppModel

    var body: some View {
        viewState
            .onContinueUserActivity(UserActivity.bundleIdentifierType) { userActivity in
                handle(userActivity: userActivity)
            }
    }

    private var viewState: AppInitialState {
        appModel.hasDatabase ? .ready : .initializing
    }

    private func handle(userActivity: NSUserActivity) {
        // SIRI & Search
        let module = UserActivity.module(from: userActivity)
        guard module != .none, let itemId = UserActivity.itemId(from: userActivity) else { return }
        let childId = UserActivity.childId(from: userActivity)
        appModel.navigator.perform(route: KnownRoutes.route(module: module, itemId: itemId, entryId: childId))
    }
}

#Preview {
    InitialRootView(appModel: .previewWithoutDatabase)
        .frame(width: 400, height: 400)
}
