// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MapPinActionButtons: View {
    let model: MapPinViewModel
    let pinId: UUID
    let layoutDown: Bool
    let glassNamespace: Namespace.ID
    let photoSpace: Namespace.ID
    let onRemove: () -> Void
    let onCopy: () -> Void
    let onResize: () -> Void
    let onPhoto: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool { model.isExpandedId == pinId }

    var body: some View {
        ZStack {
            pinButton(type: .remove, action: onRemove).zIndex(10)
            pinButton(type: .copy, action: onCopy).zIndex(10)
            pinButton(type: .photo, action: onPhoto).zIndex(10)
            pinButton(type: .resize, action: onResize).zIndex(10)

            Color.clear
#if !os(visionOS)
                .glassEffectID("menu", in: glassNamespace)
#endif
        }
    }

    private func pinButton(type: MapPinButtonType, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(type.localizedLabel)
            } icon: {
                Image(systemName: type.systemImage)
            }
                .labelStyle(.iconOnly)
                .frame(width: 50, height: 50)
        }
        .borderLessTVBottonStyle()
        .foregroundStyle(.white)
#if !os(visionOS)
        .applyIf(isExpanded) {
            $0.glassEffect(.regular.tint(NetworkModules.map.tint.opacity(0.75)).interactive())
        }
        .glassEffectID(type.label, in: glassNamespace)
#endif
        .offset(type.offset(expanded: isExpanded, layoutDown: layoutDown))
        .animation(
            reduceMotion ? nil : .spring(duration: type.duration * 3, bounce: 0.2),
            value: model.isExpandedId
        )
        .opacity(isExpanded ? 1 : 0)
        .allowsHitTesting(isExpanded)
        .accessibilityHidden(!isExpanded)
        .matchedTransitionSource(id: type.label, in: photoSpace)
    }
}

#Preview {
    @Previewable @State var model = MapPinViewModel(mapPins: [], pointer: .empty)
    @Previewable @Namespace var glassNamespace
    @Previewable @Namespace var photoSpace
    MapPinActionButtons(
        model: model,
        pinId: MapModel.previewId,
        layoutDown: true,
        glassNamespace: glassNamespace,
        photoSpace: photoSpace,
        onRemove: {},
        onCopy: {},
        onResize: {},
        onPhoto: {}
    )
}
