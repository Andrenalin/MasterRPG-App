// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct ViewerRootView: View {
    init(model: SpaceModel, dismissAction: (() -> Void)? = nil) {
        self.model = model
        self.dismissAction = dismissAction
    }
    
    let model: SpaceModel
    let dismissAction: (() -> Void)?
    
    @Environment(SpaceRootModel.self) private var root
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
        
    var body: some View {
        let _ = Self._printChanges()
        NavigationStack {
            VStack {
#if !os(tvOS)
                SpaceViewer(root: root, id: model.id, isModal: true)
                    .id(model.id)
#endif
            }
            .ignoresSafeArea(.container, edges: [.top, .bottom])
#if !os(visionOS)
            .background(colorScheme == .dark ? Color.black.ignoresSafeArea() : Color.white.ignoresSafeArea())
#endif
            .navigationTitle(Text(model.name))
#if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
        .environment(CacheItemListModel())
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(SpaceRootModel.self) var root

    ViewerRootView(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
}
