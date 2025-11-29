// @copyright André Trettin

import CoreExternalRPG
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
    @MainActor public static func root(container: ModelContainer, audioRoot: AudioRootModel, diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel, characterRoot: CharacterRootModel) -> MapRootModel {
        MapRootModel(container: container, audioRoot: audioRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, characterRoot: characterRoot)
    }
    
    @MainActor public static func rootView() -> some View {
        MapRootView()
    }
        
    @MainActor @ViewBuilder public static func detailView(root: MapRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
