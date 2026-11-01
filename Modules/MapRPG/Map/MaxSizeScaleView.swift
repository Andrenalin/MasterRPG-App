// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MaxSizeScaleView: View {
    @Bindable var model: MapEditorSession
    let onMaxWidthChanged: (Double) -> Void
    let onMaxHeightChanged: (Double) -> Void
    let onEditingChanged: (Bool) -> Void

    init(
        model: MapEditorSession,
        onMaxWidthChanged: @escaping (Double) -> Void,
        onMaxHeightChanged: @escaping (Double) -> Void,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.model = model
        self.onMaxWidthChanged = onMaxWidthChanged
        self.onMaxHeightChanged = onMaxHeightChanged
        self.onEditingChanged = onEditingChanged
    }

    var body: some View {
        VStack(spacing: 8) {
#if !os(tvOS)
            HStack {
                Text("Max Width", bundle: .module)
                    .foregroundStyle(.primary)
                Slider(
                    value: $model.maxWidthRatio,
                    in: MapEditorScaleRanges.maxSizeRatio,
                    onEditingChanged: onEditingChanged
                ) {
                    Text("Max Width", bundle: .module)
                }
                .onChange(of: model.maxWidthRatio) {
                    onMaxWidthChanged(model.maxWidthRatio)
                }
                .accessibilityValue(Text(model.maxWidthRatio, format: .percent))
                .labelsHidden()
            }

            HStack {
                Text("Max Height", bundle: .module)
                    .foregroundStyle(.primary)
                Slider(
                    value: $model.maxHeightRatio,
                    in: MapEditorScaleRanges.maxSizeRatio,
                    onEditingChanged: onEditingChanged
                ) {
                    Text("Max Height", bundle: .module)
                }
                .onChange(of: model.maxHeightRatio) {
                    onMaxHeightChanged(model.maxHeightRatio)
                }
                .accessibilityValue(Text(model.maxHeightRatio, format: .percent))
                .labelsHidden()
            }
#endif
        }
        .opacity(model.hideCloseButton ? 0 : 1)
        .allowsHitTesting(!model.hideCloseButton)
        .accessibilityHidden(model.hideCloseButton)
        .disabled(model.hideCloseButton)
    }
}

#Preview {
    @Previewable var model = MapEditorSession(
        map: .previewEmpty,
        image: AKImage(),
        photoDegrees: 0,
        containerSize: CGSize(width: 320, height: 240)
    )
    MaxSizeScaleView(
        model: model,
        onMaxWidthChanged: { _ in },
        onMaxHeightChanged: { _ in }
    )
}
