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
}

struct MapPinView: View, Equatable {
    let model: MapPinViewModel
    let pinId: UUID
    let pinSize: CGSize
    let isShown: Bool
    let borderColor: Color
    let canDrag: Bool
    let doubleTapAction: (() -> Void)?
    let dragEndAction: (() -> Void)?

    @Environment(MapRootModel.self) private var root

    @GestureState private var isDragging = false
    @State private var isDraggingStarts = false

    static func == (lhs: MapPinView, rhs: MapPinView) -> Bool {
        guard lhs.pinId == rhs.pinId,
              lhs.pinSize == rhs.pinSize,
              lhs.isShown == rhs.isShown,
              lhs.borderColor == rhs.borderColor,
              lhs.canDrag == rhs.canDrag else { return false }
        let lp = lhs.model.pinPointer(for: lhs.pinId)
        let rp = rhs.model.pinPointer(for: rhs.pinId)
        return lp?.location == rp?.location
            && lp?.size == rp?.size
            && lp?.photoId == rp?.photoId
    }

    var body: some View {
#if os(macOS)
        pinView
#else
        pinView
#endif
    }

    private var position: MapPinModel? {
        model.pinPointer(for: pinId)
    }

    private var pinView: some View {
        VStack {
            if let position {
                root.photoRoot.viewController.mapImage(root: root.photoRoot, for: position.photoId, size: pinSize, color: position.color)
            }
        }
        .clipShape(.circle)
        .padding(2)
        .frame(width: pinSize.width, height: pinSize.height)
        .padding(2)
        .background(borderColor)
        .overlay {
            isShown ? Color.clear : .green.opacity(0.5)
        }
        .clipShape(.circle)
        .shadow(color: .black, radius: 4, x: 4, y: 4)
#if os(visionOS)
        .hoverEffect(.highlight)
        .hoverEffect { effect, isActive, _ in
            effect.scaleEffect(isActive ? 1.2 : 1)
        }
#endif
        .highPriorityGesture(combinedGesture)
        .onChange(of: isDragging) {
            guard !isDragging else { return }
            isDraggingStarts = false
            dragEndAction?()
        }
    }

    private var combinedGesture: some Gesture {
        let tapGesture = TapGesture().onEnded {
            withAnimation {
                model.isExpandedId = model.isExpandedId == pinId ? nil : pinId
            }
        }
        let doubleTap = TapGesture(count: 2).onEnded {
            withAnimation { doubleTapAction?() }
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
                state = true
            }
            .onChanged { value in
                guard canDrag, var pos = position else { return }
                isDraggingStarts = true
                pos.location = CGPoint(
                    x: pos.location.x + (value.location.x - value.startLocation.x),
                    y: pos.location.y + (value.location.y - value.startLocation.y)
                )
                pos.timeInterval = Date.now.timeIntervalSince1970
                model.setPinPointer(updatedPin: pos)
            }
    }
#endif
}

#Preview {
    @Previewable var model: MapPinViewModel = MapPinViewModel(mapPins: [MapPinModel.empty(MapModel.previewId), MapPinModel.empty(UUID())], pointer: .empty(UUID()))

    MapPinView(model: model, pinId: MapModel.previewId, pinSize: model.mapPins[0].size == .normal ? CGSize(width: 64, height: 64) : CGSize(width: 128, height: 128), isShown: false, borderColor: .yellow, canDrag: true) {
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
