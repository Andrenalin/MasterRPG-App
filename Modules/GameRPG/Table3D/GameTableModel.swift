// @copyright André Trettin

#if os(visionOS)
import TabletopKit
import RealityKit
import SwiftUI
import CoreRPG
import MapRPG
import PhotoRPG
import UIKit
import os.log

@Observable @MainActor
final class GameTableModel: Sendable {
    let tabletopGame: TabletopGame
    let renderer: GameRenderer
    let observer: GameObserver
    let setup: GameSetup
    
    // References to root models for accessing game controllers
    let mapRoot: MapRootModel
    let photoRoot: PhotoRootModel
    
    var currentMapId: UUID?
    var currentMapImage: AKImage?
    var currentMapDegrees: Double = 0
    var networkActions: NetworkActions?
    var isGameMaster = false
    /// Room-visibility signature of the last rendered fog texture — pin moves
    /// broadcast mapState constantly; skip the expensive composite when the
    /// room state did not change.
    private var fogSignature: Int?

    @MainActor
    init(mapRoot: MapRootModel, photoRoot: PhotoRootModel) async {
        self.mapRoot = mapRoot
        self.photoRoot = photoRoot

        renderer = GameRenderer()
        
        // ✅ IMPORTANT: Wait for assets to load before continuing
        await renderer.loadAssets()
        
        setup = GameSetup(root: renderer.root)
        
        tabletopGame = TabletopGame(tableSetup: setup.setup)
        
        observer = GameObserver(tabletop: tabletopGame, renderer: renderer)
        tabletopGame.addObserver(observer)
        
        tabletopGame.addRenderDelegate(renderer)
        renderer.game = self

        // Note: Initial seat claiming is handled by SharePlay coordinator
        // If SharePlay is active, seats will be assigned through setupSeatAssignment
        // If not active, claim any seat for single-player mode
        // This will be called from the view when the immersive space is opened

        // Shuffles the card deck.
        self.resetGame()
    }
    
    /// Called when the 3D table view appears to set up seating
    @MainActor
    func setupSeating(sharePlayController: RPGSharePlayController) {
        let isMaster = sharePlayController.gameModel?.gameConfig.isMaster ?? false
        observer.isMaster = isMaster
        if sharePlayController.isActive, let groupSession = sharePlayController.groupSession {
            Logger.sharePlay.debug("Setting up seating with SharePlay")
            assignSeatsForSharePlay(groupSession: groupSession, isMaster: isMaster)
            sharePlayController.setupSeatAssignment(gameTableModel: self)
        } else {
            Logger.sharePlay.debug("Setting up seating for single-player")
            tabletopGame.claimAnySeat()
        }
    }
        
    @MainActor func handleMapChange(isGameMaster: Bool) async {
        self.isGameMaster = isGameMaster
        guard let currentItemId = mapRoot.gameControllable.gameModel.currentItemId else {
            Logger.gameTable.debug("No current map selected in game")
            return
        }

        // Only update if the map actually changed
        guard currentItemId != currentMapId else { return }
        currentMapId = currentItemId
        fogSignature = nil

        // Get the current map model from game controller
        guard let mapModel = await mapRoot.itemControllable.item(for: currentItemId) as? MapModel else {
            Logger.gameTable.error("Current item is not a MapModel")
            return
        }

        await loadMapPhoto(mapModel: mapModel, isGameMaster: isGameMaster)
        syncPawnsWithMapPins()
    }
    
    @MainActor
    private func loadMapPhoto(mapModel: MapModel, isGameMaster: Bool) async {
        guard let photoId = mapModel.photoId else {
            Logger.gameTable.debug("Map has no photo")
            return
        }
        
        // Fetch the photo image similar to RootCanvasMap.reloadImage()
        let (image, degrees) = await photoRoot.fetchPhotoImage(for: photoId, useGame: true) ?? (nil, 0)
        
        guard let akImage = image else {
            Logger.gameTable.error("Failed to load photo for the current map")
            return
        }
        
        // Cache the current map image and rotation for future updates
        currentMapImage = akImage
        currentMapDegrees = degrees
        fogSignature = Self.roomSignature(of: mapModel)
        
        // Update the board with the new photo, display config, and map model (for fog of war)
        setup.board.updateMap(
            image: akImage,
            degrees: degrees,
            displayConfig: mapModel.displayConfig,
            mapModel: mapModel,
            isGameMaster: isGameMaster
        )
        Logger.gameTable.debug("Map updated (rotation: \(degrees, privacy: .public)°, GM: \(isGameMaster, privacy: .public))")
    }
    
    /// Updates the fog of war when map entries change (rooms shown/hidden)
    @MainActor
    func updateFogOfWar(isGameMaster: Bool) async {
        self.isGameMaster = isGameMaster
        guard let currentItemId = currentMapId else {
            Logger.gameTable.debug("No current map to update fog of war")
            return
        }

        guard let mapModel = await mapRoot.itemControllable.item(for: currentItemId) as? MapModel else {
            Logger.gameTable.error("Current item is not a MapModel")
            return
        }

        guard let mapImage = currentMapImage else {
            await loadMapPhoto(mapModel: mapModel, isGameMaster: isGameMaster)
            return
        }

        // Pin moves arrive as mapState too — only re-composite the texture
        // when the room visibility actually changed.
        let signature = Self.roomSignature(of: mapModel)
        guard signature != fogSignature else { return }
        fogSignature = signature

        setup.board.updateMap(
            image: mapImage,
            degrees: currentMapDegrees,
            displayConfig: mapModel.displayConfig,
            mapModel: mapModel,
            isGameMaster: isGameMaster
        )
        Logger.gameTable.debug("Fog of war updated - \(mapModel.entries.filter { !$0.isShown }.count, privacy: .public) hidden areas (GM: \(isGameMaster, privacy: .public))")
    }

    private static func roomSignature(of mapModel: MapModel) -> Int {
        var hasher = Hasher()
        hasher.combine(mapModel.id)
        for entry in mapModel.entries {
            hasher.combine(entry.id)
            hasher.combine(entry.isShown)
        }
        return hasher.finalize()
    }

    /// Loads the pin's photo thumbnail (2D pin pipeline) onto the 3D token.
    @MainActor
    func loadPinThumbnail(pinId: UUID, photoId: UUID) async {
        guard let cache = photoRoot.cacheControllable else { return }
        var image = await cache.thumbnail(for: photoId)
        if image == nil {
            guard let item = await photoRoot.itemControllable.item(for: photoId) else { return }
            await cache.thumbnailId(for: photoId, item: item)
            image = await cache.thumbnail(for: photoId)
        }
        guard let image, let pawn = setup.pinPawns.first(where: { $0.pinId == pinId }) else { return }
        pawn.setPhotoTexture(image)
        pawn.loadedPhotoId = photoId
    }

    /// Game-master pin drag: follow the finger on the board plane.
    @MainActor
    func pinDragChanged(pinId: UUID, position: SIMD3<Float>) {
        guard isGameMaster, let pawn = setup.pinPawns.first(where: { $0.pinId == pinId }) else { return }
        pawn.entity.position = SIMD3<Float>(position.x, MapTableProjection.pinHeight, position.z)
    }

    /// Game-master pin drop: write the move back into the map model and
    /// broadcast the map state — the round-trip snaps every device (including
    /// this one) to the authoritative position.
    @MainActor
    func pinDragEnded(pinId: UUID, position: SIMD3<Float>) {
        guard isGameMaster, let mapId = currentMapId,
              let cgImage = currentMapImage?.cgImage else { return }
        let projection = MapTableProjection(imageSize: CGSize(width: cgImage.width, height: cgImage.height), degrees: currentMapDegrees)
        let location = projection.mapLocation(for: SIMD3<Float>(position.x, MapTableProjection.pinHeight, position.z))
        guard mapRoot.mapGameControllable.movePin(itemId: mapId, pinId: pinId, location: location) else { return }
        networkActions?.game(mapRoot.mapGameControllable.networkMapUpdate(for: mapId), .mapState, nil)
    }
    
    isolated deinit {
        tabletopGame.removeObserver(observer)
        tabletopGame.removeRenderDelegate(renderer)
    }
}

extension Logger {
    static let gameTable = Logger(subsystem: subsystem, category: "GameTable")
}

#endif
