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
import SwiftData
import SwiftUI
import RPGWeathers
import CoreExternalRPG

public enum AdventureFactory {
    @MainActor public static func root(
        container: ModelContainer,
        audioRoot: AudioRoot,
        diceRoot: DiceRoot,
        mapRoot: MapRoot,
        pdfRoot: PdfRoot,
        photoRoot: PhotoRoot,
        spaceRoot: SpaceRoot,
        tableRoot: TableRoot,
        valueRoot: ValueRoot,
        weatherRoot: WeatherRootModel
    ) -> AdventureRoot {
        AdventureRoot(
            container: container,
            audioRoot: audioRoot,
            diceRoot: diceRoot,
            mapRoot: mapRoot,
            pdfRoot: pdfRoot,
            photoRoot: photoRoot,
            spaceRoot: spaceRoot,
            tableRoot: tableRoot,
            valueRoot: valueRoot,
            weatherRoot: weatherRoot
        )
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
            .navigationAutoReceive(AdventureRoute.self)
    }
    
    @MainActor @ViewBuilder public static func detailView(root: AdventureRoot) -> some View {
        ExternalDetailView()
    }
}

struct ExternalDetailView: View {
    @Environment(AdventureRoot.self) private var root
    
    var body: some View {
        if let itemId = root.listController(tabId: KnownRoutes.mainTabId).model.selectedItem?.model.itemId {
            AdventureRoute.detail(itemId)
                .environment(root.listController(tabId: KnownRoutes.mainTabId).model)
        } else {
            SplitContentUnavailable(module: .adventure)
        }
    }
}
