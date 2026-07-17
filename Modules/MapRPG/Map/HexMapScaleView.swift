// @copyright André Trettin

import CoreRPG
import SwiftUI

struct HexMapScaleView: View {
    @Bindable var model: MapEditorSession
    let onScaleChanged: (Double) -> Void

    var body: some View {
        HStack {
#if !os(tvOS)
            Text("Hex Scale", bundle: .module)
                .foregroundStyle(.white)
            Slider(value: $model.hexScale, in: 20 ... 200) {
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

#Preview {
    @Previewable var model = MapEditorSession(
        map: .previewEmpty,
        image: AKImage(),
        photoDegrees: 0,
        containerSize: CGSize(width: 320, height: 240)
    )
    HexMapScaleView(model: model, onScaleChanged: { _ in })
}
