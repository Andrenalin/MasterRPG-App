// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MapPinActionButtons: View {
    let model: MapPinNode
    let layoutDown: Bool
    let context: MapPinActionContext
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
                .frame(width: 50, height: 50)
        }
        .borderLessTVBottonStyle()
        .foregroundStyle(.white)
#if !os(visionOS)
        .applyIf(usesGlassEffects) {
            $0.glassEffect(.regular.tint(NetworkModules.map.tint.opacity(0.75)).interactive())
        }
        .applyIf(usesGlassEffects) {
            $0.glassEffectID(type.label, in: glassNamespace)
        }
#endif
        .offset(type.offset(at: index, count: count, expanded: true, layoutDown: layoutDown))
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
        layoutDown: true,
        context: .editor,
        glassNamespace: glassNamespace,
        photoSpace: photoSpace
    )
}
