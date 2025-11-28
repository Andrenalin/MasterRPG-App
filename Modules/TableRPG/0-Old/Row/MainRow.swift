// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct MainRow: View {
    let model: TableModel
    let isSelected: Bool
    let cacheItemListModel: CacheItemListModel
    
    @Environment(TableRootModel.self) private var root
    @Environment(\.showGame) private var showGame
    @Environment(ListModel.self) private var listModel

    @Environment(\.gameModus) private var gameModus
    @Environment(\.networkActions) private var networkActions
    @Environment(\.valueActions) private var valueActions
    
    var body: some View {
        ItemRow(itemId: model.id, model: model, cacheItemListModel: cacheItemListModel, name: \.name, tags: \.tags, description: \.description, isSelected: isSelected, tagAdds: {
            CategoryItemRow(category: model.category)
        }, actionBar: {
            headerActionBar
        })
    }
    
    private var headerActionBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if showGame && gameModus == .master {
                    Button {
                        listModel.showGeneratorItem = ItemRowModel(itemId: model.id, typeId: root.itemController.itemDataModel.networkModule)
                    } label: {
                        Image(systemName: "gear")
                            .frame(height: valueFor(iOS: 30, macOS: 24, tvOS: 30, visionOS: 30))
                    }
                    .buttonStyle(.borderedProminent)
                    .contentShape(.rect)
                }
            }
            .shareListItem(isActive: showGame && gameModus == .master, feedBackEnabled: true) {
                Task {
                    await networkActions?.shareId(root.gameController.share(id: model.id))
                }
            }

            HStack {
                root.viewController.diceView(root: root, for: model.diceId, from: model.id)

                if let diceResult = model.diceResult, let diceId = model.diceId {
                    Button {
                        let loclNetworkActions = networkActions
                        let localValueActions = valueActions
                        Task { @MainActor in
                            await root.gameController.requestTableResult(for: model.id, diceId: diceId, diceResult: diceResult, networkActions: loclNetworkActions, valueActions: localValueActions)
                        }
                    } label: {
                        Label(diceResult, systemImage: NetworkModules.dice.icon)
                            .imageScale(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .contentShape(.rect)
                }
            }
        }
    }
}
