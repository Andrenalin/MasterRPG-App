// @copyright André Trettin

import AndrenalinKit
import RPGDie
import RPGAudios
import RPGMaps
import RPGPdfs
import RPGPhotos
import RPGSpaces
import RPGTables
import RPGValues
import CoreData
import SwiftUI
import RPGWeathers

public enum AdventureFactory {
    @MainActor static var sharedRoot: AdventureRoot?
    
    @MainActor
    public static func root(for context: NSManagedObjectContext, audioRoot: AudioRoot, diceRoot: DiceRoot, mapRoot: MapRoot, pdfRoot: PdfRoot, photoRoot: PhotoRoot, spaceRoot: SpaceRoot, tableRoot: TableRoot, valueRoot: ValueRoot, weatherRoot: WeatherRoot) -> AdventureRoot {
        let root = AdventureRoot(context: context, audioRoot: audioRoot, diceRoot: diceRoot, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, valueRoot: valueRoot, weatherRoot: weatherRoot)
        if sharedRoot == nil {
            sharedRoot = root
        }
        return root
    }

    @MainActor
    public static func rootView(for root: AdventureRoot, tabId: UUID) -> some View {
        RootList(root: root, tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }
    
    @MainActor
    public static func rootExtendedView(for root: AdventureRoot, tabId: UUID) -> some View {
        RootExtendedList(editController: root.editController(type: .main), tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }
}
