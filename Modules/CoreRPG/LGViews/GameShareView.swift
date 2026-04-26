// @copyright André Trettin

import SwiftUI

public struct GameShareView<Content: View>: View {
    public init(root: any ItemRootControllable, model: any ItemDataAccessable, @ViewBuilder content: () -> Content = EmptyView.init) {
        self.root = root
        self.model = model
        self.content = content()
    }

    let root: any ItemRootControllable
    let model: any ItemDataAccessable
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
            root.viewControllable.sharingView(for: model.id)
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
                await networkActions?.shareId(root.gameControllable.share(id: model.id))
            } else {
                if let result = try? await root.gameControllable.createGameData(for: model.id) {
                    networkActions?.game(result, .generic, nil)
                }
            }
        }
    }
}
