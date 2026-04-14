// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ViewerRootView: View {
    let model: WeatherModel
    let configuration: ViewerConfiguration
    var dismissAction: (() -> Void)? = nil
    
    @Environment(WeatherRootModel.self) private var root
    
    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var isAnimating: Bool = false
    
    var body: some View {
        VStack {
            GeometryReader { proxy in
                WeatherViewer(model: model, size: proxy.size, useGame: configuration.isGame, isAnimating: $isAnimating)
                    .id(model.id)
            }
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .applyIf(!configuration.isGame) {
            $0.toolbar {
                toolbarContent
            }
            .navigationTitle(Text(model.name))
    #if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
    #endif
        }
#if !os(visionOS)
        .background(colorScheme == .dark ? Color.black.ignoresSafeArea() : Color.white.ignoresSafeArea())
#endif
        .environment(root.editController.cacheItemListModel)
        .onAppear {
            guard configuration.isGame else { return }
            withAnimation { isAnimating = true }
        }
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
        
        ToolbarItem(placement: .primaryAction) {
            animateButton
        }
    }
    
    var shouldShowCloseButton: Bool {
        valueFor(iOS: appSizeModel.mode == .compact || dismissAction != nil, macOS: false, tvOS: dismissAction != nil, visionOS: dismissAction != nil)
    }

    var animateButton: some View {
        Button {
            withAnimation { isAnimating.toggle() }
        } label: {
            Image(systemName: "film\(isAnimating ? ".fill" : "")")
        }
        .contentTransition(.symbolEffect(.replace.wholeSymbol))
#if os(macOS)
                .foregroundStyle(root.config.module.tint)
#else
                .tint(root.config.module.tint)
#endif
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
#if os(macOS)
                .foregroundStyle(root.config.module.tint)
#else
                .tint(root.config.module.tint)
#endif
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(WeatherRootModel.self) var root
    
    ViewerRootView(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]), configuration: ViewerConfiguration())
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
}
