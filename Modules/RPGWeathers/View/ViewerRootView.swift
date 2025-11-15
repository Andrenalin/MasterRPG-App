// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct ViewerRootView: View {
    init(model: WeatherModel, dismissAction: (() -> Void)? = nil) {
        self.model = model
        self.dismissAction = dismissAction
    }
    
    let model: WeatherModel
    let dismissAction: (() -> Void)?
    
    @Environment(WeatherRootModel.self) private var root
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
        
    var body: some View {
        let _ = Self._printChanges()
        NavigationStack {
            VStack {
                GeometryReader { proxy in
                    WeatherViewer(model: model, size: proxy.size, useGame: false)
                        .id(model.id)
                }
            }
            .ignoresSafeArea(.container, edges: [.top, .bottom])
#if !os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    closeButton
                }
            }
#endif
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

private extension ViewerRootView {
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
        //.opacity(showGame ? 0 : 1)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(WeatherRootModel.self) var root
        
    ViewerRootView(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
}
