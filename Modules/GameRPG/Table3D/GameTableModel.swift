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
    weak var mapRoot: MapRootModel?
    weak var photoRoot: PhotoRootModel?
    
    private var currentMapId: UUID?

    @MainActor
    init() async {
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
    
    @MainActor
    func configure(mapRoot: MapRootModel, photoRoot: PhotoRootModel) {
        self.mapRoot = mapRoot
        self.photoRoot = photoRoot
        
        // Optionally load the current map immediately if one exists
        Task {
            await handleMapChange()
        }
    }
        
    @MainActor
    func handleMapChange() async {
        guard let mapRoot = mapRoot,
              let photoRoot = photoRoot else {
            print("MapRoot or PhotoRoot not configured")
            return
        }
        
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
        await loadMapPhoto(mapModel: mapModel, photoRoot: photoRoot)
    }
    
    @MainActor
    private func loadMapPhoto(mapModel: MapModel, photoRoot: PhotoRootModel) async {
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
        
        guard let imageData = akImage.pngData() else {
            print("Failed to convert image to PNG data")
            return
        }
        
        // Update the board with the new photo
        setup.board.updateMap(from: imageData)
        print("Map updated successfully: '\(mapModel.name)' (rotation: \(degrees)°)")
    }
    
    deinit {
        tabletopGame.removeObserver(observer)
        tabletopGame.removeRenderDelegate(renderer)
    }
}

#endif
