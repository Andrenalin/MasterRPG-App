// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MapPinActionButtons: View {
    let model: MapPinViewModel
    let pin: MapPinModel
    let layoutDown: Bool
    let context: MapPinActionContext
    let glassNamespace: Namespace.ID
    let photoSpace: Namespace.ID
    var usesGlassEffects: Bool = true
    let action: (MapPinButtonType) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool { model.isExpandedId == pin.id }

    var body: some View {
        ZStack {
            ForEach(context.actions.enumerated(), id: \.element) { index, type in
                pinButton(type: type, index: index, count: context.actions.count)
                    .zIndex(10)
            }

            Color.clear
#if !os(visionOS)
                .applyIf(usesGlassEffects) {
                    $0.glassEffectID("menu", in: glassNamespace)
                }
#endif
        }
    }

    private func pinButton(type: MapPinButtonType, index: Int, count: Int) -> some View {
        Button {
            action(type)
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
        .applyIf(usesGlassEffects && isExpanded) {
            $0.glassEffect(.regular.tint(NetworkModules.map.tint.opacity(0.75)).interactive())
        }
        .applyIf(usesGlassEffects) {
            $0.glassEffectID(type.label, in: glassNamespace)
        }
#endif
        .offset(type.offset(at: index, count: count, expanded: isExpanded, layoutDown: layoutDown))
        .animation(
            reduceMotion ? nil : .spring(duration: (0.3 + CGFloat(index) * 0.1) * 3, bounce: 0.2),
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
        pin: .empty(MapModel.previewId),
        layoutDown: true,
        context: .editor,
        glassNamespace: glassNamespace,
        photoSpace: photoSpace,
        action: { _ in }
    )
}
