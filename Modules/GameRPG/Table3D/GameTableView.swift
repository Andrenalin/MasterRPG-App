// @copyright André Trettin

#if os(visionOS)
import Foundation
import GroupActivities
import RealityKit
import SwiftUI
import TabletopKit

@MainActor
public struct GameTableView: View {
    let root: GameRoot
    
    @Environment(\.realityKitScene) private var scene
    @State private var game: GameTableModel?
    @State private var activityManager: GroupActivityManager?

    public init(root: GameRoot) {
        self.root = root
    }

    public var body: some View {
        GeometryReader3D { proxy in
            if let loadedGame = game, activityManager != nil {
                RealityView { (content: inout RealityViewContent) in
                    content.entities.append(loadedGame.renderer.root)
                    content.add(loadedGame.renderer.portalWorld)
                    content.add(loadedGame.renderer.portal)
                }.toolbar() {
                    GameTableToolbar(game: loadedGame)
                }.tabletopGame(loadedGame.tabletopGame, parent: loadedGame.renderer.root) { _ in
                    GameInteraction(game: loadedGame)
                }
            }
        }
        .task {
            let initGame = await GameTableModel()
            self.root.gameModel.gameTableModel = initGame
            //self.root.gameModel.gameTableModel?.configure(mapRoot: root.mapRoot, photoRoot: root.photoRoot)
            self.game = initGame
            self.activityManager = .init(tabletopGame: initGame.tabletopGame)
        }
    }
}

#endif
