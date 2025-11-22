// @copyright André Trettin

import AndrenalinKit
import RPGDie
import AudioRPG
import RPGMaps
import PdfRPG
import PhotoRPG
import SpaceRPG
import RPGTables
import RPGValues
import SwiftData
import SwiftUI
import WeatherRPG
import CoreExternalRPG

public enum AdventureFactory {
    @MainActor public static func root(
        container: ModelContainer,
        audioRoot: AudioRootModel,
        diceRoot: DiceRootModel,
        mapRoot: MapRootModel,
        pdfRoot: PdfRootModel,
        photoRoot: PhotoRootModel,
        spaceRoot: SpaceRootModel,
        tableRoot: TableRootModel,
        valueRoot: CharacterRootModel,
        weatherRoot: WeatherRootModel
    ) -> AdventureRootModel {
        AdventureRootModel(
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
    public static func rootView(for root: AdventureRootModel, tabId: UUID) -> some View {
        RootList(root: root, tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
    }
    
    @MainActor
    public static func rootExtendedView(for root: AdventureRootModel, tabId: UUID) -> some View {
        RootExtendedList(editController: root.editController(type: .main), tabId: tabId, selection: true)
            .itemSplitViewSizeMode(.wide)
            .navigationAutoReceive(AdventureRoute.self)
    }
    
    @MainActor @ViewBuilder public static func detailView(root: AdventureRootModel) -> some View {
        ExternalDetailView()
    }
}

struct ExternalDetailView: View {
    @Environment(AdventureRootModel.self) private var root
    
    var body: some View {
        if let itemId = root.listController(tabId: KnownRoutes.mainTabId).model.selectedItem?.model.itemId {
            AdventureRoute.detail(itemId)
                .environment(root.listController(tabId: KnownRoutes.mainTabId).model)
        } else {
            SplitContentUnavailable(module: .adventure)
        }
    }
}
