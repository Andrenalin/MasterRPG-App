// @copyright André Trettin

import CoreRPG
import SwiftUI

enum HexMapScaleAppearance {
    case editor
    case gameOverlay
}

struct HexMapScaleView: View {
    @Bindable var model: MapEditorSession
    let appearance: HexMapScaleAppearance
    let onToggle: () -> Void
    let onScaleChanged: (Double) -> Void
    let onScaleEditingChanged: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        model: MapEditorSession,
        appearance: HexMapScaleAppearance = .editor,
        onToggle: @escaping () -> Void,
        onScaleChanged: @escaping (Double) -> Void,
        onScaleEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.model = model
        self.appearance = appearance
        self.onToggle = onToggle
        self.onScaleChanged = onScaleChanged
        self.onScaleEditingChanged = onScaleEditingChanged
    }

    var body: some View {
        HStack {
#if !os(tvOS)
            Button {
                withAnimation(reduceMotion ? nil : .default) {
                    onToggle()
                }
            } label: {
                let symbolName = model.isHexMap ? "hexagon.fill" : "hexagon"
                Image(systemName: symbolName)
                    .contentTransition(.symbolEffect(.replace.wholeSymbol))
                    .frame(width: 24, height: 24)
                    .accessibilityLabel(Text("Hex Grid", bundle: .module))
                    .accessibilityValue(
                        model.isHexMap
                            ? Text("Enabled", bundle: .module)
                            : Text("Disabled", bundle: .module)
                    )
            }
            .modifier(
                HexMapScaleButtonModifier(
                    appearance: appearance,
                    isSelected: model.isHexMap
                )
            )

            Text("Hex Scale", bundle: .module)
                .foregroundStyle(.primary)
            Slider(
                value: $model.hexScale,
                in: MapEditorScaleRanges.hexScale,
                onEditingChanged: onScaleEditingChanged
            ) {
                Text("Hex Scale", bundle: .module)
            }
            .onChange(of: model.hexScale) {
                onScaleChanged(model.hexScale)
            }
            .accessibilityValue(model.hexScale.formatted(.number.precision(.fractionLength(0))))
            .labelsHidden()
#endif
        }
        .opacity(model.hideCloseButton ? 0 : 1)
        .allowsHitTesting(!model.hideCloseButton)
        .accessibilityHidden(model.hideCloseButton)
    }
}

private struct HexMapScaleButtonModifier: ViewModifier {
    let appearance: HexMapScaleAppearance
    let isSelected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        switch appearance {
        case .editor:
            content.buttonStyle(.bordered)
        case .gameOverlay:
            content
                .frame(minWidth: 44, minHeight: 44)
                .gameOverlayControlStyle(isSelected: isSelected)
        }
    }
}

#Preview {
    @Previewable var model = MapEditorSession(
        map: .previewEmpty,
        image: AKImage(),
        photoDegrees: 0,
        containerSize: CGSize(width: 320, height: 240)
    )
    HexMapScaleView(
        model: model,
        onToggle: { model.isHexMap.toggle() },
        onScaleChanged: { _ in }
    )
}
