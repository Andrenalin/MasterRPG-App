// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AdventureSheet: View {
    let model: AdventureModel
    let configuration: ViewerConfiguration
    let searchContext: SheetSearchContext?
    let dismissAction: (() -> Void)?

    init(
        model: AdventureModel,
        configuration: ViewerConfiguration,
        searchContext: SheetSearchContext? = nil,
        dismissAction: (() -> Void)?
    ) {
        self.model = model
        self.configuration = configuration
        self.searchContext = searchContext
        self.dismissAction = dismissAction
    }

    @Environment(AdventureRootModel.self) private var root

    var body: some View {
        TableRootSheet(
            root: root.rootController,
            itemId: model.id,
            module: root.config.module,
            configuration: configuration,
            searchContext: searchContext,
            dismissAction: dismissAction
        )
            .id(model.id)
    }
}

#Preview(traits: .mockData) { AdventureSheet(model: .preview, configuration: .init(), dismissAction: nil) }
