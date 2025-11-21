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
        
    @State private var isAnimating: Bool = false
    
    var body: some View {
        let _ = Self._printChanges()
        NavigationStack {
            VStack {
                GeometryReader { proxy in
                    WeatherViewer(model: model, size: proxy.size, useGame: false, isAnimating: $isAnimating)
                        .id(model.id)
                }
            }
            .ignoresSafeArea(.container, edges: [.top, .bottom])
#if !os(macOS)
            .toolbar {
                toolbarContent
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
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            closeButton
        }
        
        ToolbarItem(placement: .primaryAction) {
            animateButton
        }
    }
    
    var animateButton: some View {
        Button {
            withAnimation { isAnimating.toggle() }
        } label: {
            Image(systemName: "film\(isAnimating ? ".fill" : "")")
        }
        .contentTransition(.symbolEffect(.replace.wholeSymbol))
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
