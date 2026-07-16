// @copyright André Trettin

#if os(visionOS)
import Combine
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
    @State private var accessibilitySubscriptions: [any Cancellable] = []

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

                    if accessibilitySubscriptions.isEmpty,
                       let gameScene = loadedGame.renderer.root.scene {
                        let subscription = gameScene.subscribe(to: AccessibilityEvents.Activate.self) { event in
                            guard let pinId = event.entity.components[PinComponent.self]?.pinId else { return }
                            loadedGame.pinTapped(pinId: pinId)
                        }
                        accessibilitySubscriptions.append(subscription)
                    }

                    // Place the table on the actual floor of the volume. The volume is
                    // flatter than Apple's 1.5 m sample (and the system may clamp the
                    // requested size), so the fixed rootOffset would clip the scene.
                    let volumeBounds = content.convert(proxy.frame(in: .local), from: .local, to: .scene)
                    loadedGame.renderer.placeTable(bottomY: volumeBounds.min.y)

                    if let panel = attachments.entity(for: "toolbar") {
                        panel.position = SIMD3<Float>(0, 0, Float(GameMetrics.tableEdge) + 0.1)
                        loadedGame.renderer.root.addChild(panel)
                    }

                    // ✅ Debug logging
                    #if DEBUG
                    print("✅ Root added with \(loadedGame.renderer.root.children.count) children")
                    print("   Position: \(loadedGame.renderer.root.position)")
                    print("   Scale: \(loadedGame.renderer.root.scale)")
                    print("   Volume bounds: \(volumeBounds)")
                    #endif
                } update: { content, _ in
                    // Re-anchor to the volume floor when the user resizes the volume.
                    let volumeBounds = content.convert(proxy.frame(in: .local), from: .local, to: .scene)
                    loadedGame.renderer.placeTable(bottomY: volumeBounds.min.y)
                } attachments: {
                    Attachment(id: "toolbar") {
                        GameTableToolbar(game: loadedGame)
                    }
                }
                .tabletopGame(loadedGame.tabletopGame, parent: loadedGame.renderer.root) { _ in
                    GameInteraction(game: loadedGame)
                }
                // Pin drag: the handlers guard permissions — the master moves
                // every pin, a player only its own.
                // Uses simultaneousGesture so TabletopKit's own gesture recognisers
                // do not consume the event before it reaches the pin entities.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5)
                        .targetedToEntity(where: .has(PinComponent.self))
                        .onChanged { value in
                            guard let pinId = value.entity.components[PinComponent.self]?.pinId,
                                  let parent = value.entity.parent else { return }
                            let position = value.convert(value.location3D, from: .local, to: parent)
                            loadedGame.pinDragChanged(pinId: pinId, position: position)
                        }
                        .onEnded { value in
                            guard let pinId = value.entity.components[PinComponent.self]?.pinId,
                                  let parent = value.entity.parent else { return }
                            let position = value.convert(value.location3D, from: .local, to: parent)
                            loadedGame.pinDragEnded(pinId: pinId, position: position)
                        }
                )
                // Double tap: master hides/shows the pin. Single tap: ×4 zoom
                // for everyone, like the 2D viewer.
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .targetedToEntity(where: .has(PinComponent.self))
                        .exclusively(before: TapGesture().targetedToEntity(where: .has(PinComponent.self)))
                        .onEnded { value in
                            switch value {
                            case .first(let doubleTap):
                                guard let pinId = doubleTap.entity.components[PinComponent.self]?.pinId else { return }
                                loadedGame.pinDoubleTapped(pinId: pinId)
                            case .second(let tap):
                                guard let pinId = tap.entity.components[PinComponent.self]?.pinId else { return }
                                loadedGame.pinTapped(pinId: pinId)
                            }
                        }
                )
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

            // The volume can open after a map is already revealed — bring the
            // table up to date immediately instead of waiting for the next
            // mapState round-trip.
            initGame.networkActions = root.networkActions
            initGame.isGameMaster = root.gameModel.gameConfig.isMaster
            initGame.playerPinId = initGame.isGameMaster ? nil : root.gameModel.gameConfig.id
            await initGame.handleMapChange(isGameMaster: initGame.isGameMaster)
            initGame.syncPawnsWithMapPins()
            
            // ✅ Verify initialization
            #if DEBUG
            print("✅ GameTableModel initialized")
            print("   TabletopGame: \(initGame.tabletopGame)")
            print("   ActivityManager: \(String(describing: activityManager))")
            print("   SharePlay active: \(root.networkStore.sharePlayStore.isActive)")
            #endif
        }
        .onDisappear {
            accessibilitySubscriptions.removeAll()
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

#Preview {
    GameTableView(root: .preview)
}

#endif
