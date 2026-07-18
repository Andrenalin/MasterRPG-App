// @copyright André Trettin

#if os(visionOS)
import Combine
import CoreRPG
import Foundation
import GroupActivities
import MapRPG
import RealityKit
import SwiftUI
import TabletopKit

@MainActor
public struct GameTableView: View {
    let root: GameRoot
    
    @State private var game: GameTableModel?
    @State private var activityManager: GroupActivityManager?
    @State private var scaleController = TableScaleGestureController()
    @State private var accessibilitySubscriptions: [any Cancellable] = []

    public init(root: GameRoot) {
        self.root = root
    }

    public var body: some View {
        GeometryReader3D { proxy in
            if let loadedGame = game {
                RealityView { content, attachments in
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
                        let zoomSubscription = gameScene.subscribe(to: AccessibilityEvents.CustomAction.self) { event in
                            guard let pinId = event.entity.components[PinComponent.self]?.pinId else { return }
                            loadedGame.pinDoubleTapped(pinId: pinId)
                        }
                        accessibilitySubscriptions.append(zoomSubscription)
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

                    if let pinMenu = attachments.entity(for: "pin-menu") {
                        loadedGame.registerPinMenuAttachment(pinMenu)
                    }

                } update: { content, _ in
                    // Re-anchor to the volume floor when the user resizes the volume.
                    let volumeBounds = content.convert(proxy.frame(in: .local), from: .local, to: .scene)
                    loadedGame.renderer.placeTable(bottomY: volumeBounds.min.y)
                    loadedGame.updatePinMenuAttachmentPosition()
                } attachments: {
                    Attachment(id: "toolbar") {
                        GameTableToolbar(game: loadedGame)
                    }
                    Attachment(id: "pin-menu") {
                        GamePinActionMenu(game: loadedGame)
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
                // Double tap toggles shared zoom for both roles. Single tap
                // opens the master's local menu or toggles a shared player
                // highlight. Exclusivity prevents a double tap also firing the
                // single-tap action.
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
            await initializeGameIfNeeded()
        }
        .task(id: root.mapRoot.gameControllable.gameModel.currentItemId) {
            guard let game else { return }
            await game.handleMapChange(
                isGameMaster: root.gameModel.gameConfig.isMaster
            )
        }
        .task {
            await scaleController.start()
        }
        .onDisappear {
            accessibilitySubscriptions.removeAll()
            root.gameModel.shareState.mode = .window
            root.networkStore.sharePlayStore.applyShareState()
            if root.gameModel.gameTableModel === game {
                root.gameModel.gameTableModel = nil
            }
        }
    }

    private func initializeGameIfNeeded() async {
        if let game {
            // A volumetric window can disappear without discarding its @State.
            // Re-register the retained model instead of rebuilding the complete
            // TabletopKit graph and loading its package assets again.
            root.gameModel.gameTableModel = game
            scaleController.renderer = game.renderer
            root.gameModel.shareState.mode = .tabletop
            root.networkStore.sharePlayStore.applyShareState()
            configureSessionState(for: game)
            await game.handleMapChange(isGameMaster: game.isGameMaster)
            return
        }

        let initializedGame = GameTableModel(
            mapRoot: root.mapRoot,
            photoRoot: root.photoRoot
        )
        await initializedGame.renderer.loadAssets()
        guard !Task.isCancelled else { return }

        root.gameModel.gameTableModel = initializedGame
        game = initializedGame
        scaleController.renderer = initializedGame.renderer
        root.gameModel.shareState.mode = .tabletop
        root.networkStore.sharePlayStore.applyShareState()

        activityManager = .init(
            tabletopGame: initializedGame.tabletopGame,
            sharePlayController: root.networkStore.sharePlayStore
        )
        initializedGame.setupSeating(
            sharePlayController: root.networkStore.sharePlayStore
        )
        configureSessionState(for: initializedGame)

        // The volume can open after a map is already revealed — bring the
        // table up to date immediately instead of waiting for a mapState trip.
        await initializedGame.handleMapChange(
            isGameMaster: initializedGame.isGameMaster
        )
        guard !Task.isCancelled else { return }
        initializedGame.syncPawnsWithMapPins()
    }

    private func configureSessionState(for game: GameTableModel) {
        game.networkActions = root.networkActions
        game.isGameMaster = root.gameModel.gameConfig.isMaster
        game.playerPinId = game.isGameMaster ? nil : root.gameModel.gameConfig.id
    }
}

#Preview {
    GameTableView(root: .preview)
}

#endif

#if os(iOS) || os(macOS)
import Combine
import CoreRPG
import MapRPG
import RealityKit
import SwiftUI

/// Camera-based 3D table for iOS and macOS. It intentionally shares the game
/// model and map/pin synchronization with the visionOS table while leaving all
/// TabletopKit session behavior in the visionOS implementation above.
@MainActor
public struct GameTableView: View {
    let root: GameRoot
    private let retentionModel: GameScreenModel?
    private let showsEmbeddedToolbar: Bool

    @State private var game: GameTableModel?
    @State private var accessibilitySubscriptions: [any Cancellable] = []

    public init(root: GameRoot) {
        self.root = root
        retentionModel = nil
        showsEmbeddedToolbar = true
    }

    init(root: GameRoot, retentionModel: GameScreenModel?) {
        self.root = root
        self.retentionModel = retentionModel
        showsEmbeddedToolbar = false
    }

    public var body: some View {
        Group {
            if let game {
                GameTableRealityContent(
                    game: game,
                    accessibilitySubscriptions: $accessibilitySubscriptions,
                    showsEmbeddedToolbar: showsEmbeddedToolbar
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.black.gradient)
        .task {
            await initializeGameIfNeeded()
        }
        .task(id: root.mapRoot.gameControllable.gameModel.currentItemId) {
            guard let game else { return }
            await game.handleMapChange(
                isGameMaster: root.gameModel.gameConfig.isMaster
            )
        }
        .onDisappear {
            accessibilitySubscriptions.removeAll()
            retentionModel?.retainedGameTableModel = game
            if root.gameModel.gameTableModel === game {
                root.gameModel.gameTableModel = nil
            }
        }
    }

    private func initializeGameIfNeeded() async {
        if let game {
            // SwiftUI may temporarily disappear without destroying @State.
            // Restore the root registration so network controllers continue
            // driving the still-live table after it appears again.
            root.gameModel.gameTableModel = game
            await game.handleMapChange(
                isGameMaster: root.gameModel.gameConfig.isMaster
            )
            return
        }

        if let retainedGame = retentionModel?.retainedGameTableModel {
            retainedGame.networkActions = root.networkActions
            retainedGame.isGameMaster = root.gameModel.gameConfig.isMaster
            retainedGame.playerPinId = retainedGame.isGameMaster
                ? nil
                : root.gameModel.gameConfig.id
            game = retainedGame
            root.gameModel.gameTableModel = retainedGame
            await retainedGame.handleMapChange(
                isGameMaster: retainedGame.isGameMaster
            )
            return
        }

        let initializedGame = GameTableModel(
            mapRoot: root.mapRoot,
            photoRoot: root.photoRoot
        )
        await initializedGame.renderer.loadAssets()
        guard !Task.isCancelled else { return }

        initializedGame.networkActions = root.networkActions
        initializedGame.isGameMaster = root.gameModel.gameConfig.isMaster
        initializedGame.playerPinId = initializedGame.isGameMaster
            ? nil
            : root.gameModel.gameConfig.id
        root.gameModel.gameTableModel = initializedGame
        game = initializedGame

        await initializedGame.handleMapChange(
            isGameMaster: initializedGame.isGameMaster
        )
        guard !Task.isCancelled else { return }
        initializedGame.syncPawnsWithMapPins()
    }
}

/// Explicit name for callers that want to distinguish the camera-based table
/// from the volumetric visionOS TabletopKit view.
public typealias GameTableRealityView = GameTableView

@MainActor
private struct GameTableRealityContent: View {
    let game: GameTableModel
    @Binding var accessibilitySubscriptions: [any Cancellable]
    let showsEmbeddedToolbar: Bool

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            content.add(game.renderer.root)
            content.cameraTarget = game.setup.board.entity
            installAccessibilitySubscriptionsIfNeeded()
        } update: { content in
            content.camera = .virtual
            content.cameraTarget = game.setup.board.entity
        }
        .realityViewCameraControls(.orbit)
        .simultaneousGesture(pinDragGesture)
        .simultaneousGesture(pinTapGesture)
        .overlay(alignment: .topTrailing) {
            if showsEmbeddedToolbar {
                GameTableToolbar(game: game)
                    .padding()
            }
        }
        .overlay(alignment: .bottom) {
            GamePinActionMenu(game: game)
                .padding()
        }
    }

    private var pinDragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .targetedToEntity(where: .has(PinComponent.self))
            .onChanged { value in
                guard let pinId = value.entity.components[PinComponent.self]?.pinId,
                      let parent = value.entity.parent,
                      let position = value.tablePosition(relativeTo: parent) else { return }
                game.pinDragChanged(pinId: pinId, position: position)
            }
            .onEnded { value in
                guard let pinId = value.entity.components[PinComponent.self]?.pinId,
                      let parent = value.entity.parent,
                      let position = value.tablePosition(relativeTo: parent) else { return }
                game.pinDragEnded(pinId: pinId, position: position)
            }
    }

    private var pinTapGesture: some Gesture {
        TapGesture(count: 2)
            .targetedToEntity(where: .has(PinComponent.self))
            .exclusively(
                before: TapGesture()
                    .targetedToEntity(where: .has(PinComponent.self))
            )
            .onEnded { value in
                switch value {
                case .first(let doubleTap):
                    guard let pinId = doubleTap.entity.components[PinComponent.self]?.pinId else { return }
                    game.pinDoubleTapped(pinId: pinId)
                case .second(let tap):
                    guard let pinId = tap.entity.components[PinComponent.self]?.pinId else { return }
                    game.pinTapped(pinId: pinId)
                }
            }
    }

    private func installAccessibilitySubscriptionsIfNeeded() {
        guard accessibilitySubscriptions.isEmpty,
              let scene = game.renderer.root.scene else { return }

        let activate = scene.subscribe(to: AccessibilityEvents.Activate.self) { event in
            guard let pinId = event.entity.components[PinComponent.self]?.pinId else { return }
            Task { @MainActor in
                game.pinTapped(pinId: pinId)
            }
        }
        let zoom = scene.subscribe(to: AccessibilityEvents.CustomAction.self) { event in
            guard let pinId = event.entity.components[PinComponent.self]?.pinId else { return }
            Task { @MainActor in
                game.pinDoubleTapped(pinId: pinId)
            }
        }
        accessibilitySubscriptions = [activate, zoom]
    }
}

private extension EntityTargetValue where Value == DragGesture.Value {
    @MainActor
    func tablePosition(relativeTo parent: Entity) -> SIMD3<Float>? {
        guard let ray = ray(
            through: self.location,
            in: .local,
            to: parent
        ), abs(ray.direction.y) > 0.000_001 else { return nil }

        let distance = (MapTableProjection.pinHeight - ray.origin.y) / ray.direction.y
        guard distance.isFinite, distance >= 0 else { return nil }
        return ray.origin + ray.direction * distance
    }
}

#Preview("3D Table") {
    GameTableView(root: .preview)
}
#endif
