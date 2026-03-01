// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

@Observable
final class MapPinViewModel {
    init(mapPins: [MapPinModel], pointer: MapPinModel) {
        self.mapPins = mapPins
        self.pointer = pointer
    }
    
    var mapPins: [MapPinModel]
    var pointer: MapPinModel
    var isExpandedId: UUID?
    
    func pinPointer(for id: UUID) -> MapPinModel? {
        if pointer.id == id {
            return pointer
        }
        if let index = mapPins.firstIndex(where: { $0.id == id }) {
            return mapPins[index]
        }
        return nil
    }
    
    func setPinPointer(updatedPin: MapPinModel) {
        if pointer.id == updatedPin.id {
            pointer = updatedPin
        } else if let index = mapPins.firstIndex(where: { $0.id == updatedPin.id }) {
            mapPins[index] = updatedPin
        }
    }
    
    func removePin(id: UUID) {
        mapPins.removeAll(where: { $0.id == id })
        if isExpandedId == id {
            isExpandedId = nil
        }
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
    let tapAction: (() -> Void)?
    let doubleTapAction: (() -> Void)?
    let dragEndAction: (() -> Void)?
    
    @Environment(MapRootModel.self) private var root
    
    @GestureState private var isDragging = false
    @State private var isDraggingStarts = false
    
    // Equatable implementation: compare stable properties that affect rendering
    static func == (lhs: MapPinView, rhs: MapPinView) -> Bool {
        lhs.pinId == rhs.pinId &&
        lhs.pinSize == rhs.pinSize &&
        lhs.isShown == rhs.isShown &&
        lhs.borderColor == rhs.borderColor &&
        lhs.canDrag == rhs.canDrag &&
        lhs.model.pinPointer(for: lhs.pinId)?.location == rhs.model.pinPointer(for: rhs.pinId)?.location &&
        lhs.model.pinPointer(for: lhs.pinId)?.size == rhs.model.pinPointer(for: rhs.pinId)?.size &&
        lhs.model.pinPointer(for: lhs.pinId)?.photoId == rhs.model.pinPointer(for: rhs.pinId)?.photoId
    }
    
    var body: some View {
#if os(macOS)
        pinView
#else
        Button {
            guard !isDraggingStarts else { return }
            withAnimation {
                tapAction?()
            }
        } label: {
            pinView
#if os(visionOS)
                .hoverEffect(.highlight)
                .hoverEffect { effect, isActive, _ in
                    effect.scaleEffect(isActive ? 1.2 : 1)
                }
#endif
        }
        .buttonStyle(.borderless)
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
        .padding(3)
        .frame(width: pinSize.width , height: pinSize.height)
        .padding(3)
        .background(borderColor)
        .overlay {
            isShown ? Color.clear : .green.opacity(0.5)
        }
        .clipShape(.circle)
        .shadow(color: .black, radius: 4, x: 4, y: 4)
        .highPriorityGesture(combinedGesture)
        .onChange(of: isDragging) {
            guard !isDragging else { return }
            Task {
                isDraggingStarts = false
                dragEndAction?()
            }
        }
    }
    
    private var combinedGesture: some Gesture {
        let tapGesture = TapGesture().onEnded {
            withAnimation {
                tapAction?()
            }
        }
        return doubeDragGesture.exclusively(before: tapGesture)
    }
    
    private var doubeDragGesture: some Gesture {
#if os(tvOS)
        doubeTapGesture
#else
        dragGesture.simultaneously(with: doubeTapGesture)
#endif
    }
    
    private var doubeTapGesture: some Gesture {
        TapGesture(count: 2).onEnded {
            withAnimation { doubleTapAction?() }
        }
    }
#if !os(tvOS)
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3).updating($isDragging) { value, state, _ in
            guard canDrag else {
                state = false
                return
            }
            Task {
                isDraggingStarts = true
                guard var position = position else { return }
                let x = position.location.x + (value.location.x - value.startLocation.x)
                let y = position.location.y + (value.location.y - value.startLocation.y)
                position.location = CGPoint(x: x, y: y)
                position.timeInterval = Date.now.timeIntervalSince1970
                model.setPinPointer(updatedPin: position)
            }
            state = true
        }
    }
#endif
}

#Preview {
    @Previewable var model: MapPinViewModel = MapPinViewModel(mapPins: [MapPinModel.empty(MapModel.previewId), MapPinModel.empty(UUID())], pointer: .empty(UUID()))
    
    MapPinView(model: model, pinId: MapModel.previewId, pinSize: model.mapPins[0].size == .normal ? CGSize(width: 64, height: 64) : CGSize(width: 128, height: 128), isShown: false, borderColor: .yellow, canDrag: true) {
        var pin = model.mapPins[0]
        pin.size = pin.size == .normal ? .large : .normal
        model.setPinPointer(updatedPin: pin)
    } doubleTapAction: {
        var pin = model.mapPins[0]
        pin.isShown.toggle()
        model.setPinPointer(updatedPin: pin)
    } dragEndAction: {
        print("end")
    }
    .offset(x: model.mapPins[0].location.x, y: model.mapPins[0].location.y)
    .environment(MapRootModel.preview)
}
