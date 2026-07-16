// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MaxSizeScaleView: View {
    @Bindable var model: MapEditorModel
    let onMaxWidthChanged: (Double) -> Void
    let onMaxHeightChanged: (Double) -> Void

    var body: some View {
        VStack(spacing: 8) {
#if !os(tvOS)
            HStack {
                Text("Max Width", bundle: .module)
                    .foregroundStyle(.white)
                Slider(value: $model.maxWidthRatio, in: 0.1 ... 1.0) {
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
                    .foregroundStyle(.white)
                Slider(value: $model.maxHeightRatio, in: 0.1 ... 1.0) {
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
    }
}

#Preview {
    @Previewable var model = MapEditorModel(
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
