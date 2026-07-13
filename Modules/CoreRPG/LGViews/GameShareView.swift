// @copyright André Trettin

import SwiftUI

public struct GameShareView<Content: View>: View {
    public init(root: any ItemRootControllable, itemId: UUID, @ViewBuilder content: () -> Content = EmptyView.init) {
        self.root = root
        self.itemId = itemId
        self.content = content()
    }

    let root: any ItemRootControllable
    let itemId: UUID
    let content: Content
        
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.networkActions) private var networkActions
    @Environment(\.sharingFeatureActions) private var sharingFeatureActions

    public var body: some View {
        actionBarWithSharing
    }
    
    @ViewBuilder
    var actionBarWithSharing: some View {
        switch root.viewControllable.sharingViewType {
        case .none:
            content
        case .share:
            content
                .shareListItem(isActive: canShare, feedBackEnabled: true, action: shareAction)
        case .custom:
            root.viewControllable.sharingView(for: itemId)
        }
    }
    
    var canShare: Bool {
        if appGameStateModel.gameModus == .player {
            let features = sharingFeatureActions.features()
            switch root.configurable.module {
            case .photo:
                return features.photoSharing && appGameStateModel.isGameRunning
            case .audio:
                return features.audioSharing && appGameStateModel.isGameRunning
            case .space:
                return features.spaceSharing && appGameStateModel.isGameRunning
            default:
                return false
            }
        } else {
            return appGameStateModel.isGameRunning
        }
    }
    
    func shareAction() {
        Task {
            if appGameStateModel.gameModus == .master {
                await networkActions?.shareId(root.gameControllable.share(id: itemId))
            } else {
                if let result = try? await root.gameControllable.createGameData(for: itemId) {
                    networkActions?.game(result, .generic, nil)
                }
            }
        }
    }
}

#Preview {
    GameShareView(root: ItemRootController.fake, itemId: UUID()) {
        Label("Share item", systemImage: "square.and.arrow.up")
    }
    .environment(AppGameStateModel())
}
