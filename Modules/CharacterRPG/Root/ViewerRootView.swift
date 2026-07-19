// @copyright André Trettin

import CoreRPG
import SwiftUI
import PhotoRPG

@MainActor
struct ViewerRootView: View {
    let model: ValueModel
    let configuration: ViewerConfiguration
    let searchContext: SheetSearchContext?
    let dismissAction: (() -> Void)?

    init(
        model: ValueModel,
        configuration: ViewerConfiguration,
        searchContext: SheetSearchContext? = nil,
        dismissAction: (() -> Void)?
    ) {
        self.model = model
        self.configuration = configuration
        self.searchContext = searchContext
        self.dismissAction = dismissAction
    }
    
    @Environment(CharacterRootModel.self) private var root

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

#Preview {
    ViewerRootView(model: .preview, configuration: ViewerConfiguration(), dismissAction: nil)
        .environment(CharacterRootModel.previewWithData)
}
