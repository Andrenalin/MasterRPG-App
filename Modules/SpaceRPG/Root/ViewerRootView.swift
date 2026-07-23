// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ViewerRootView: View {
    let model: SpaceModel
    let configuration: ViewerConfiguration
    var dismissAction: (() -> Void)? = nil

    @Environment(SpaceRootModel.self) private var root
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
#if !os(tvOS)
            SpaceViewer(root: root, id: model.id, isModal: configuration.addToolbar)
                .id(model.id)
#endif
        }
        .ignoresSafeArea(.container, edges: ignoredSafeAreaEdges)
        .applyIf(configuration.addToolbar) {
            $0.toolbar {
                toolbarContent
            }
            .navigationTitle(Text(verbatim: model.name))
            .navigationBarTitleDisplayModeAll(.inline)
        }
#if !os(visionOS)
        .background(.black.gradient)
#endif
        .environment(CacheItemListModel())
    }

    private var ignoredSafeAreaEdges: Edge.Set {
        configuration.addToolbar || configuration.isGame ? [.top, .bottom] : []
    }
}

private extension ViewerRootView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        if configuration.closeButton {
            ToolbarItem(placement: .cancellationAction) {
                closeButton
            }
        }
    }

    var closeButton: some View {
        Button {
            if let dismissAction {
                dismissAction()
            } else {
                dismiss()
            }
        } label: {
            Label {
                Text("Close", bundle: .module)
            } icon: {
                Image(systemName: "xmark.circle")
            }
            .labelStyle(.iconOnly)
        }
#if os(macOS)
                .moduleForegroundStyle(root.config.module)
#else
                .moduleTint(root.config.module)
#endif
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(SpaceRootModel.self) var root

    ViewerRootView(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]), configuration: ViewerConfiguration())
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
}
