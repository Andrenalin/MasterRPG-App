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
    @State private var scaleController = TableScaleGestureController()

    public init(root: GameRoot) {
        self.root = root
    }

    public var body: some View {
        GeometryReader3D { proxy in
            if let loadedGame = game, activityManager != nil {
                RealityView { content, attachments in
                    content.entities.append(loadedGame.renderer.root)
                    content.add(loadedGame.renderer.portalWorld)
                    content.add(loadedGame.renderer.portal)
                    if let panel = attachments.entity(for: "toolbar") {
                        // 10 cm in front of the table's front edge, at table-surface height.
                        // Parented to root so it scales with the table gesture.
                        panel.position = SIMD3<Float>(0, 0, Float(GameMetrics.tableEdge) + 0.1)
                        loadedGame.renderer.root.addChild(panel)
                    }
                } attachments: {
                    Attachment(id: "toolbar") {
                        GameTableToolbar(game: loadedGame)
                    }
                }
                .tabletopGame(loadedGame.tabletopGame, parent: loadedGame.renderer.root) { _ in
                    GameInteraction(game: loadedGame)
                }
            }
        }
        .task {
            let initGame = await GameTableModel(mapRoot: root.mapRoot, photoRoot: root.photoRoot)
            self.root.gameModel.gameTableModel = initGame
            self.game = initGame
            scaleController.renderer = initGame.renderer
            root.gameModel.shareState.mode = .tabletop
            root.networkStore.sharePlayStore.applyShareState()
            self.activityManager = .init(tabletopGame: initGame.tabletopGame, sharePlayController: root.networkStore.sharePlayStore)
            initGame.setupSeating(sharePlayController: root.networkStore.sharePlayStore)
        }
        .task {
            await scaleController.start()
        }
        .onDisappear {
            root.gameModel.shareState.mode = .window
            root.networkStore.sharePlayStore.applyShareState()
            root.gameModel.gameTableModel = nil
        }
    }
}

#endif
