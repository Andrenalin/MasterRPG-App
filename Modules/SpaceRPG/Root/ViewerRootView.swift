// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ViewerRootView: View {
    let model: SpaceModel
    var windowMode: Bool = false
    var externalViewer: Bool = true
    var dismissAction: (() -> Void)? = nil

    @Environment(SpaceRootModel.self) private var root
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appSizeMode) private var appSizeMode

    var body: some View {
        VStack {
#if !os(tvOS)
            SpaceViewer(root: root, id: model.id, isModal: externalViewer)
                .id(model.id)
#endif
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .applyIf(externalViewer) {
            $0.toolbar {
                toolbarContent
            }
            .navigationTitle(Text(model.name))
#if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
#if !os(visionOS)
        .background(.black.gradient)
#endif
        .environment(CacheItemListModel())
    }
}

private extension ViewerRootView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        if shouldShowCloseButton {
            ToolbarItem(placement: .cancellationAction) {
                closeButton
            }
        }
    }
    
    var shouldShowCloseButton: Bool {
        valueFor(iOS: appSizeMode == .compact || dismissAction != nil, macOS: false, tvOS: dismissAction != nil, visionOS: dismissAction != nil)
    }

    var closeButton: some View {
        Button {
            if let dismissAction {
                dismissAction()
            } else {
                dismiss()
            }
        } label: {
            Image(systemName: "xmark.circle")
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(SpaceRootModel.self) var root

    ViewerRootView(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
}
