// @copyright André Trettin


import CoreRPG
import AudioRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG
import CharacterRPG
import SwiftData
import SwiftUI

public enum MapRootFactory {
    @MainActor public static func root(tagController: TagController, audioRoot: AudioRootModel, diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel, characterRoot: CharacterRootModel) -> MapRootModel {
        MapRootModel(tagController: tagController, audioRoot: audioRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, characterRoot: characterRoot)
    }
    
    @MainActor public static func rootView() -> some View {
        MapRootView()
    }
        
    @MainActor public static func detailView(root: MapRootModel) -> some View {
        // Extract observable property to break dependency chain
        let selectedItemId = root.navigationModel.selectedItemId

        if let itemId = selectedItemId {
            ItemSplitDetailRouteRootView(root: root.rootController, route: MapRoute.detail(itemId))
        }
    }
}
