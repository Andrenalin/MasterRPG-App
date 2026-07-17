// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

@MainActor @Observable
final class MapPinViewModel {
    init(mapPins: [MapPinModel], pointer: MapPinModel) {
        self.mapPins = mapPins
        self.pointer = pointer
    }

    var mapPins: [MapPinModel]
    var pointer: MapPinModel
    var isExpandedId: UUID?

    func pinPointer(for id: UUID) -> MapPinModel? {
        if pointer.id == id { return pointer }
        return mapPins.first { $0.id == id }
    }

    func setPinPointer(updatedPin: MapPinModel) {
        if pointer.id == updatedPin.id {
            pointer = updatedPin
        } else if let index = mapPins.firstIndex(where: { $0.id == updatedPin.id }) {
            mapPins[index] = updatedPin
        }
    }

    func removePin(id: UUID) {
        mapPins.removeAll { $0.id == id }
        if isExpandedId == id { isExpandedId = nil }
    }

    func replacePhoto(pinId: UUID, itemId: UUID?) {
        guard var updatedPin = pinPointer(for: pinId) else { return }
        updatedPin.photoId = itemId
        setPinPointer(updatedPin: updatedPin)
    }

    func copyPin(id: UUID) {
        guard var pin = pinPointer(for: id) else { return }
        pin.id = UUID()
        pin.location = pin.location + (pin.size.size.width + 25)
        if let index = mapPins.firstIndex(where: { $0.id == id }), index != mapPins.endIndex {
            mapPins.insert(pin, at: index)
        } else {
            mapPins.append(pin)
        }
    }

    func resizePin(id: UUID) {
        guard var updatedPin = pinPointer(for: id) else { return }
        updatedPin.size = updatedPin.size.nextSize()
        setPinPointer(updatedPin: updatedPin)
    }

    func toggleDeadPin(id: UUID) {
        guard var updatedPin = pinPointer(for: id) else { return }
        updatedPin.isDead.toggle()
        setPinPointer(updatedPin: updatedPin)
    }
}

struct MapPinView: View {
    let pin: MapPinModel
    let pinSize: CGSize
    let canMove: Bool
    let doubleTapAccessibilityLabel: LocalizedStringResource
    let doubleTapAction: (() -> Void)?
    let moveAction: ((CGSize) -> Void)?
    var tapAction: (() -> Void)? = nil

    @Environment(MapRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        pinView
    }

    private var pinView: some View {
        root.photoRoot.viewController.mapImage(
            root: root.photoRoot,
            for: pin.photoId,
            size: pinSize,
            color: pin.color
        )
        .frame(width: pinSize.width, height: pinSize.height)
        .overlay {
            if !pin.isShown {
                Circle()
                    .fill(.green.opacity(0.5))
                    .accessibilityHidden(true)
            }
        }
        .clipShape(.circle)
        .overlay {
            Circle()
                .strokeBorder(pin.isDead ? .black : .gray, lineWidth: pin.isDead ? 5 : 2)
                .accessibilityHidden(true)
        }
        .overlay {
            if pin.isDead {
                Image(systemName: "xmark")
                    .resizable()
                    .scaledToFit()
                    .padding(min(pinSize.width, pinSize.height) * 0.24)
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 1, x: 1, y: 1)
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            if pin.isHighlighted {
                Circle()
                    .stroke(.red, lineWidth: 4)
                    .padding(-4)
                    .accessibilityHidden(true)
            }
        }
        .shadow(color: .black, radius: 4, x: 4, y: 4)
#if os(visionOS)
        .hoverEffect(.highlight)
        .hoverEffect { effect, isActive, _ in
            effect.scaleEffect(isActive ? 1.2 : 1)
        }
#endif
        .gesture(combinedGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pinAccessibilityLabel)
        .accessibilityValue(pinAccessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            handleTap()
        }
        .accessibilityAction(named: Text(doubleTapAccessibilityLabel)) {
            guard let doubleTapAction else { return }
            withAnimation(reduceMotion ? nil : .default) {
                doubleTapAction()
            }
        }
#if !os(tvOS)
        .accessibilityAction(named: Text("Move Left", bundle: .module)) {
            movePinBy(x: -10, y: 0)
        }
        .accessibilityAction(named: Text("Move Right", bundle: .module)) {
            movePinBy(x: 10, y: 0)
        }
        .accessibilityAction(named: Text("Move Up", bundle: .module)) {
            movePinBy(x: 0, y: -10)
        }
        .accessibilityAction(named: Text("Move Down", bundle: .module)) {
            movePinBy(x: 0, y: 10)
        }
#endif
    }

    private var combinedGesture: some Gesture {
        let tapGesture = TapGesture().onEnded {
            handleTap()
        }
        let doubleTap = TapGesture(count: 2).onEnded {
            withAnimation(reduceMotion ? nil : .default) { doubleTapAction?() }
        }
        return doubleTap.exclusively(before: tapGesture)
    }

#if !os(tvOS)
    private func movePinBy(x: CGFloat, y: CGFloat) {
        guard canMove else { return }
        moveAction?(CGSize(width: x, height: y))
    }
#endif

    private var pinAccessibilityLabel: Text {
        guard !pin.name.isEmpty else {
            return Text("Map Pin", bundle: .module)
        }
        return Text(verbatim: pin.name)
    }

    private var pinAccessibilityValue: Text {
        Text(pinAccessibilityValueResource)
    }

    private var pinAccessibilityValueResource: LocalizedStringResource {
        switch (pin.isShown, pin.isDead, pin.isHighlighted) {
        case (true, false, false): LocalizedStringResource("Visible to Players, Alive, Not Highlighted", bundle: .module)
        case (true, false, true): LocalizedStringResource("Visible to Players, Alive, Highlighted", bundle: .module)
        case (true, true, false): LocalizedStringResource("Visible to Players, Dead, Not Highlighted", bundle: .module)
        case (true, true, true): LocalizedStringResource("Visible to Players, Dead, Highlighted", bundle: .module)
        case (false, false, false): LocalizedStringResource("Hidden from Players, Alive, Not Highlighted", bundle: .module)
        case (false, false, true): LocalizedStringResource("Hidden from Players, Alive, Highlighted", bundle: .module)
        case (false, true, false): LocalizedStringResource("Hidden from Players, Dead, Not Highlighted", bundle: .module)
        case (false, true, true): LocalizedStringResource("Hidden from Players, Dead, Highlighted", bundle: .module)
        }
    }

    private func handleTap() {
        withAnimation(reduceMotion ? nil : .default) {
            tapAction?()
        }
    }
}

#Preview {
    @Previewable var model: MapPinViewModel = MapPinViewModel(mapPins: [MapPinModel.empty(MapModel.previewId), MapPinModel.empty(UUID())], pointer: .empty(UUID()))

    MapPinView(
        pin: model.mapPins[0],
        pinSize: model.mapPins[0].size == .normal ? CGSize(width: 64, height: 64) : CGSize(width: 128, height: 128),
        canMove: true,
        doubleTapAccessibilityLabel: LocalizedStringResource("Toggle Player Visibility", bundle: .module),
        doubleTapAction: {
            var pin = model.mapPins[0]
            pin.isShown.toggle()
            model.setPinPointer(updatedPin: pin)
        },
        moveAction: { translation in
            var pin = model.mapPins[0]
            pin.location = pin.location + translation
            model.setPinPointer(updatedPin: pin)
        },
        tapAction: {
            model.isExpandedId = model.isExpandedId == model.mapPins[0].id
                ? nil
                : model.mapPins[0].id
        }
    )
    .onChange(of: model.isExpandedId) {
        withAnimation {
            var pin = model.mapPins[0]
            pin.size = pin.size == .normal ? .large : .normal
            model.setPinPointer(updatedPin: pin)
        }
    }
    .offset(x: model.mapPins[0].location.x, y: model.mapPins[0].location.y)
    .environment(MapRootModel.preview)
}
