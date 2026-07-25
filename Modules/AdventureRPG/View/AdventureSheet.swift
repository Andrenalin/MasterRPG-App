// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import SwiftUI

struct AdventureSheet: View {
    let model: AdventureModel
    let configuration: ViewerConfiguration
    let dismissAction: (() -> Void)?

    init(
        model: AdventureModel,
        configuration: ViewerConfiguration,
        dismissAction: (() -> Void)?
    ) {
        self.model = model
        self.configuration = configuration
        self.dismissAction = dismissAction
    }

    @Environment(AdventureRootModel.self) private var root

    @ViewBuilder
    var body: some View {
#if os(tvOS)
        readerSheet
#else
        if configuration.isGame {
            TableRootSheet(
                root: root.rootController,
                itemId: model.id,
                module: root.config.module,
                configuration: configuration,
                dismissAction: dismissAction,
                isEditor: false,
                linkTypes: LinkAdventureModuleTransferable.self
            ) { sheetRootModel in
                SheetAIAssistantContent(
                    module: root.configurable.module,
                    itemId: model.id,
                    rootModel: sheetRootModel
                )
            }
            .id(model.id)
        } else {
            readerSheet
        }
#endif
    }

    private var readerSheet: some View {
        TableRootSheet(
            root: root.rootController,
            itemId: model.id,
            module: root.config.module,
            configuration: configuration,
            dismissAction: dismissAction
        )
        .id(model.id)
    }
}

#Preview(traits: .mockData) { AdventureSheet(model: .preview, configuration: .init(), dismissAction: nil) }
