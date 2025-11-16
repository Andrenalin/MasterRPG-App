// @copyright André Trettin

import AndrenalinKit
import RPGPhotos
import SwiftUI

@Observable
final class MapPinViewModel {
    init(mapPins: [MapPinModel], pointer: MapPinModel) {
        self.mapPins = mapPins
        self.pointer = pointer
    }
    
    var mapPins: [MapPinModel]
    var pointer: MapPinModel
    
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
}

struct MapPinView: View {
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
            Task { @MainActor in
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
            Task { @MainActor in
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
