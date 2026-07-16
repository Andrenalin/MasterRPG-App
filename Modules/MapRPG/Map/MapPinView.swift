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

struct MapPinView: View, Equatable {
    let model: MapPinViewModel
    let pin: MapPinModel
    let pinSize: CGSize
    let canDrag: Bool
    let opensActionMenu: Bool
    let doubleTapAccessibilityLabel: LocalizedStringResource
    let doubleTapAction: (() -> Void)?
    let dragEndAction: (() -> Void)?
    var tapAction: (() -> Void)? = nil

    @Environment(MapRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @GestureState private var isDragging = false
    @State private var isDraggingStarts = false
    @State private var dragStartLocation: CGPoint?

    static func == (lhs: MapPinView, rhs: MapPinView) -> Bool {
        lhs.pin == rhs.pin
            && lhs.model.isExpandedId == rhs.model.isExpandedId
            && lhs.pinSize == rhs.pinSize
            && lhs.canDrag == rhs.canDrag
            && lhs.opensActionMenu == rhs.opensActionMenu
            && lhs.doubleTapAccessibilityLabel == rhs.doubleTapAccessibilityLabel
    }

    var body: some View {
#if os(macOS)
        pinView
#else
        pinView
#endif
    }

    private var position: MapPinModel? {
        model.pinPointer(for: pin.id)
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
        .highPriorityGesture(combinedGesture)
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
        .onChange(of: isDragging) {
            guard !isDragging, isDraggingStarts else { return }
            isDraggingStarts = false
            dragStartLocation = nil
            dragEndAction?()
        }
    }

    private var combinedGesture: some Gesture {
        let tapGesture = TapGesture().onEnded {
            handleTap()
        }
        let doubleTap = TapGesture(count: 2).onEnded {
            withAnimation(reduceMotion ? nil : .default) { doubleTapAction?() }
        }
#if os(tvOS)
        return doubleTap.exclusively(before: tapGesture)
#else
        return dragGesture.simultaneously(with: doubleTap.exclusively(before: tapGesture))
#endif
    }

#if !os(tvOS)
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .updating($isDragging) { _, state, _ in
                guard canDrag else { return }
                state = true
            }
            .onChanged { value in
                guard canDrag, var pos = position else { return }
                isDraggingStarts = true
                let startLocation = dragStartLocation ?? pos.location
                if dragStartLocation == nil {
                    dragStartLocation = startLocation
                }
                pos.location = CGPoint(
                    x: startLocation.x + (value.location.x - value.startLocation.x),
                    y: startLocation.y + (value.location.y - value.startLocation.y)
                )
                pos.timeInterval = max(
                    Date.now.timeIntervalSince1970,
                    pos.timeInterval.nextUp
                )
                model.setPinPointer(updatedPin: pos)
            }
    }

    private func movePinBy(x: CGFloat, y: CGFloat) {
        guard canDrag, var updatedPin = position else { return }
        updatedPin.location.x += x
        updatedPin.location.y += y
        updatedPin.timeInterval = max(
            Date.now.timeIntervalSince1970,
            updatedPin.timeInterval.nextUp
        )
        model.setPinPointer(updatedPin: updatedPin)
        dragEndAction?()
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
            if opensActionMenu {
                model.isExpandedId = model.isExpandedId == pin.id ? nil : pin.id
            }
            tapAction?()
        }
    }
}

#Preview {
    @Previewable var model: MapPinViewModel = MapPinViewModel(mapPins: [MapPinModel.empty(MapModel.previewId), MapPinModel.empty(UUID())], pointer: .empty(UUID()))

    MapPinView(
        model: model,
        pin: model.mapPins[0],
        pinSize: model.mapPins[0].size == .normal ? CGSize(width: 64, height: 64) : CGSize(width: 128, height: 128),
        canDrag: true,
        opensActionMenu: true,
        doubleTapAccessibilityLabel: LocalizedStringResource("Toggle Player Visibility", bundle: .module)
    ) {
        var pin = model.mapPins[0]
        pin.isShown.toggle()
        model.setPinPointer(updatedPin: pin)
    } dragEndAction: {
        print("end")
    }
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
