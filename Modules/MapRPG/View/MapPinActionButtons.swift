// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MapPinActionButtons: View {
    let model: MapPinNode
    let context: MapPinActionContext
    let placement: MapAdaptiveFanPlacement
    let glassNamespace: Namespace.ID
    let photoSpace: Namespace.ID
    var usesGlassEffects: Bool = true

    private var pin: MapPinModel { model.pin }

    var body: some View {
        ZStack {
            ForEach(context.actions.enumerated(), id: \.element) { index, type in
                pinButton(type: type, index: index, count: context.actions.count)
                    .zIndex(Double(index + 1))
            }
        }
    }

    private func pinButton(type: MapPinButtonType, index: Int, count: Int) -> some View {
        Button {
            model.perform(type, context: context)
        } label: {
            Label {
                Text(type.localizedLabel(for: pin))
            } icon: {
                Image(systemName: type.systemImage(for: pin))
            }
                .labelStyle(.iconOnly)
                .frame(
                    width: MapAdaptiveFanGeometry.buttonSize.width,
                    height: MapAdaptiveFanGeometry.buttonSize.height
                )
        }
        .borderLessTVBottonStyle()
        .foregroundStyle(.white)
        .background(type.tint(for: pin).opacity(0.78), in: .circle)
        .help(Text(type.localizedLabel(for: pin)))
        .position(placement.center(at: index) ?? placement.sourceAnchor)
#if !os(visionOS)
        .applyIf(usesGlassEffects) {
            $0.glassEffect(.regular.tint(type.tint(for: pin).opacity(0.8)).interactive())
        }
        .applyIf(usesGlassEffects) {
            $0.glassEffectID(type.label, in: glassNamespace)
        }
#endif
        .contentShape(.circle)
        .applyIf(type == .photo) {
            $0.matchedTransitionSource(id: type.label, in: photoSpace)
        }
    }
}

#Preview {
    @Previewable @Namespace var glassNamespace
    @Previewable @Namespace var photoSpace
    @Previewable var model = MapPinViewModel(
        mapPins: [.empty(MapModel.previewId)],
        pointer: .empty
    )
    MapPinActionButtons(
        model: model.mapPinNodes[0],
        context: .editor,
        placement: MapAdaptiveFanGeometry.placement(
            anchor: CGPoint(x: 200, y: 200),
            itemCount: MapPinActionContext.editor.actions.count,
            viewport: CGRect(x: 0, y: 0, width: 400, height: 400)
        ),
        glassNamespace: glassNamespace,
        photoSpace: photoSpace
    )
}
