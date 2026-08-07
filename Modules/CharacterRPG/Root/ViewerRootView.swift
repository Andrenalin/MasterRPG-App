// @copyright André Trettin

import CoreRPG
import SwiftUI
import PhotoRPG

@MainActor
struct ViewerRootView: View {
    let model: ValueModel
    let configuration: ViewerConfiguration
    let dismissAction: (() -> Void)?

    init(
        model: ValueModel,
        configuration: ViewerConfiguration,
        dismissAction: (() -> Void)?
    ) {
        self.model = model
        self.configuration = configuration
        self.dismissAction = dismissAction
    }
    
    @Environment(CharacterRootModel.self) private var root

    @ViewBuilder
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
#if os(tvOS)
        readerSheet
#else
        if configuration.isGame {
            readerSheet
                .characterAddEntryOverlay(root: root, itemId: model.id)
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

#Preview("Andrenalin", traits: .mockData) {
    ViewerRootView(model: .preview, configuration: .init(), dismissAction: nil)
}

#Preview("Mira", traits: .mockData) {
    ViewerRootView(model: .previewAllEntryTypes, configuration: .init(), dismissAction: nil)
}
