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

@Observable
final class GameTableModel {
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

    @MainActor
    init(mapRoot: MapRootModel, photoRoot: PhotoRootModel) async {
        self.mapRoot = mapRoot
        self.photoRoot = photoRoot

        renderer = GameRenderer()
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
        guard let currentItemId = mapRoot.gameControllable.gameModel.currentItemId else {
            print("No current map selected in game")
            return
        }
        
        // Only update if the map actually changed
        guard currentItemId != currentMapId else { return }
        currentMapId = currentItemId
        
        print("Map changed to item: \(currentItemId)")
        
        // Get the current map model from game controller
        guard let mapModel = await mapRoot.itemControllable.item(for: currentItemId) as? MapModel else {
            print("Current item is not a MapModel")
            return
        }
        
        // Load the map photo with the game master flag
        await loadMapPhoto(mapModel: mapModel, isGameMaster: isGameMaster)
    }
    
    @MainActor
    private func loadMapPhoto(mapModel: MapModel, isGameMaster: Bool) async {
        guard let photoId = mapModel.photoId else {
            print("Map '\(mapModel.name)' has no photo")
            return
        }
        
        // Fetch the photo image similar to RootCanvasMap.reloadImage()
        let (image, degrees) = await photoRoot.fetchPhotoImage(for: photoId, useGame: true) ?? (nil, 0)
        
        guard let akImage = image else {
            print("Failed to load photo for map '\(mapModel.name)'")
            return
        }
        
        // Cache the current map image and rotation for future updates
        currentMapImage = akImage
        currentMapDegrees = degrees
        
        // Update the board with the new photo, display config, and map model (for fog of war)
        setup.board.updateMap(
            image: akImage,
            degrees: degrees,
            displayConfig: mapModel.displayConfig,
            mapModel: mapModel,
            isGameMaster: isGameMaster
        )
        print("Map updated successfully: '\(mapModel.name)' (rotation: \(degrees)°, GM: \(isGameMaster))")
    }
    
    /// Updates the fog of war when map entries change (rooms shown/hidden)
    @MainActor
    func updateFogOfWar(isGameMaster: Bool) async {
        guard let currentItemId = currentMapId else {
            print("No current map to update fog of war")
            return
        }
        
        guard let mapModel = await mapRoot.itemControllable.item(for: currentItemId) as? MapModel else {
            print("Current item is not a MapModel")
            return
        }
        
        guard let mapImage = currentMapImage else {
            print("No cached map image - loading full map")
            await loadMapPhoto(mapModel: mapModel, isGameMaster: isGameMaster)
            return
        }
        
        print("🔄 Updating fog of war for map '\(mapModel.name)'")
        
        // Regenerate the texture with updated fog of war
        setup.board.updateMap(
            image: mapImage,
            degrees: currentMapDegrees,
            displayConfig: mapModel.displayConfig,
            mapModel: mapModel,
            isGameMaster: isGameMaster
        )
        
        print("✅ Fog of war updated - \(mapModel.entries.filter { !$0.isShown }.count) hidden areas (GM: \(isGameMaster))")
    }
    
    deinit {
        tabletopGame.removeObserver(observer)
        tabletopGame.removeRenderDelegate(renderer)
    }
}

#endif
