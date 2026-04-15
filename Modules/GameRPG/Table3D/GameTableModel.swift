// @copyright André Trettin

#if os(visionOS)
import TabletopKit
import RealityKit
import SwiftUI
import CoreRPG
import MapRPG
import PhotoRPG
import UIKit

@Observable
final class GameTableModel {
    let tabletopGame: TabletopGame
    let renderer: GameRenderer
    let observer: GameObserver
    let setup: GameSetup
    
    // References to root models for accessing game controllers
    let mapRoot: MapRootModel
    let photoRoot: PhotoRootModel
    
    private var currentMapId: UUID?

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

        // Claim any seat when launching in single-player mode; a player must be seated to interact with the game.
        tabletopGame.claimAnySeat()

        // Shuffles the card deck.
        self.resetGame()
    }
        
    @MainActor func handleMapChange() async {
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
        
        // Load the map photo similar to RootCanvasMap's reloadImage()
        await loadMapPhoto(mapModel: mapModel)
    }
    
    @MainActor
    private func loadMapPhoto(mapModel: MapModel) async {
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
        
        // Update the board with the new photo, display config, and map model (for fog of war)
        setup.board.updateMap(image: akImage, degrees: degrees, displayConfig: mapModel.displayConfig, mapModel: mapModel)
        print("Map updated successfully: '\(mapModel.name)' (rotation: \(degrees)°)")
    }
    
    deinit {
        tabletopGame.removeObserver(observer)
        tabletopGame.removeRenderDelegate(renderer)
    }
}

#endif
