// @copyright André Trettin

import CoreRPG
import SwiftUI

struct PinScaleView: View {
    @Bindable var model: MapEditorSession

    var body: some View {
        HStack {
#if !os(tvOS)
            Text("Pin Scale", bundle: .module)
                .foregroundStyle(.primary)
            Slider(value: $model.pinScale, in: 0.5 ... 3.5) {
                Text("Pin Scale", bundle: .module)
            }
            .accessibilityValue(
                Double(model.pinScale).formatted(
                    FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
                ) + "×"
            )
            .labelsHidden()
#endif
        }
        .opacity(model.hideCloseButton ? 0 : 1)
        .allowsHitTesting(!model.hideCloseButton)
        .accessibilityHidden(model.hideCloseButton)
    }
}

#Preview {
    @Previewable var model = MapEditorSession(
        map: .previewEmpty,
        image: AKImage(),
        photoDegrees: 0,
        containerSize: CGSize(width: 320, height: 240)
    )
    PinScaleView(model: model)
}
