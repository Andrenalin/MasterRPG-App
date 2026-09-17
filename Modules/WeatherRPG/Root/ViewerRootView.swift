// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ViewerRootView: View {
    let model: WeatherModel
    let configuration: ViewerConfiguration
    var dismissAction: (() -> Void)? = nil
    
    @Environment(WeatherRootModel.self) private var root
    
    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var isAnimating: Bool = false

    var body: some View {
        VStack {
            WeatherViewerContainer(model: model, useGame: configuration.isGame, isAnimating: $isAnimating) {
                $0.id(model.id)
            }
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .applyIf(!configuration.isGame) {
            $0.toolbar {
                toolbarContent
            }
            .navigationTitle(Text(model.name))
            .navigationBarTitleDisplayModeAll(.inline)
        }
#if !os(visionOS)
        .background(colorScheme == .dark ? Color.black.ignoresSafeArea() : Color.white.ignoresSafeArea())
#endif
        .environment(root.editController.cacheItemListModel)
        .onAppear {
            guard configuration.isGame else { return }
            withAnimation(accessibilityReduceMotion ? nil : .default) {
                isAnimating = true
            }
        }
    }
}

private extension ViewerRootView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        if shouldShowCloseButton {
            ToolbarItem(placement: .cancellationAction) {
                WeatherCloseButtonView(dismissAction: dismissAction)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            WeatherAnimateButtonView(isAnimating: $isAnimating)
        }
    }

    var shouldShowCloseButton: Bool {
        valueFor(iOS: appSizeModel.mode == .compact || dismissAction != nil, macOS: false, tvOS: dismissAction != nil, visionOS: dismissAction != nil)
    }
}

private struct WeatherAnimateButtonView: View {
    @Binding var isAnimating: Bool

    @Environment(WeatherRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Button {
            withAnimation(accessibilityReduceMotion ? nil : .default) {
                isAnimating.toggle()
            }
        } label: {
            Label {
                Text("Animate", bundle: .module)
            } icon: {
                Image(systemName: "film\(isAnimating ? ".fill" : "")")
            }
        }
        .labelStyle(.iconOnly)
        .accessibilityValue(
            isAnimating ? Text("On", bundle: .module) : Text("Off", bundle: .module)
        )
        .contentTransition(.symbolEffect(.replace.wholeSymbol))
#if os(macOS)
                .moduleForegroundStyle(root.config.module)
#else
                .moduleTint(root.config.module)
#endif
    }
}

private struct WeatherCloseButtonView: View {
    var dismissAction: (() -> Void)?

    @Environment(WeatherRootModel.self) private var root
    @Environment(\.dismiss) private var dismiss

    var body: some View {
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
        }
        .labelStyle(.iconOnly)
#if os(macOS)
                .moduleForegroundStyle(root.config.module)
#else
                .moduleTint(root.config.module)
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
