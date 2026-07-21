// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ViewerRootView: View {
    let model: RuleModel
    let configuration: ViewerConfiguration
    var dismissAction: (() -> Void)?

    @Environment(RuleRootModel.self) private var root

    var body: some View {
        TableRootSheet(
            root: root.rootController,
            itemId: model.id,
            module: .rule,
            configuration: configuration,
            dismissAction: dismissAction,
            isEditor: false,
            linkTypes: LinkRuleData.self
        ) { _ in
            EmptyView()
        }
        .safeAreaInset(edge: .top) {
            if !model.sourceMetadata.isEmpty {
                RuleSourceDisclosureView(metadata: model.sourceMetadata)
#if os(tvOS)
                    .background(Color.clear)
#else
                    .background(.bar)
#endif
            }
        }
        .id(model.id)
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        ViewerRootView(model: .preview, configuration: ViewerConfiguration())
    }
}
