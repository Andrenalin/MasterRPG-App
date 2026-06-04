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
            if let loadedGame = game {  // ✅ Removed activityManager check - it was blocking render!
                RealityView { content, attachments in
                    // ✅ Use .add() consistently
                    content.add(loadedGame.renderer.root)
                    content.add(loadedGame.renderer.portalWorld)
                    content.add(loadedGame.renderer.portal)
                    
                    if let panel = attachments.entity(for: "toolbar") {
                        panel.position = SIMD3<Float>(0, 0, Float(GameMetrics.tableEdge) + 0.1)
                        loadedGame.renderer.root.addChild(panel)
                    }
                    
                    // ✅ Debug logging
                    #if DEBUG
                    print("✅ Root added with \(loadedGame.renderer.root.children.count) children")
                    print("   Position: \(loadedGame.renderer.root.position)")
                    print("   Scale: \(loadedGame.renderer.root.scale)")
                    #endif
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
            #if DEBUG
            print("🚀 GameTableView.task: Starting initialization...")
            #endif
            
            let initGame = await GameTableModel(mapRoot: root.mapRoot, photoRoot: root.photoRoot)
            self.root.gameModel.gameTableModel = initGame
            
            #if DEBUG
            print("✅ GameTableModel created, setting game state...")
            #endif
            
            self.game = initGame  // This will trigger RealityView to render
            scaleController.renderer = initGame.renderer
            root.gameModel.shareState.mode = .tabletop
            
            #if DEBUG
            print("📡 Applying SharePlay state...")
            #endif
            
            root.networkStore.sharePlayStore.applyShareState()
            
            #if DEBUG
            print("🎮 Creating GroupActivityManager...")
            #endif
            
            self.activityManager = .init(tabletopGame: initGame.tabletopGame, sharePlayController: root.networkStore.sharePlayStore)
            initGame.setupSeating(sharePlayController: root.networkStore.sharePlayStore)
            
            // ✅ Verify initialization
            #if DEBUG
            print("✅ GameTableModel initialized")
            print("   TabletopGame: \(initGame.tabletopGame)")
            print("   ActivityManager: \(String(describing: activityManager))")
            print("   SharePlay active: \(root.networkStore.sharePlayStore.isActive)")
            #endif
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
