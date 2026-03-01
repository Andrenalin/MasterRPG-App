// @copyright André Trettin

import CoreRPG
import SwiftUI

enum MapPinButtonType: String {
    case remove, copy, photo, resize
    
    var systemImage: String {
        switch self {
        case .remove:
            return "trash"
        case .copy:
            return "document.on.document"
        case .photo:
            return "photo"
        case .resize:
            return "square.resize"
        }
    }
    
    var label: String {
        self.rawValue.capitalized
    }
    
    var duration: CGFloat {
        switch self {
        case .remove:
            return 0.3
        case .copy:
            return 0.4
        case .photo:
            return 0.5
        case .resize:
            return 0.6
        }
    }
    
    func offset(expanded: Bool, layoutDown: Bool) -> CGSize {
        guard expanded else {
            return .zero
        }
        
        switch self {
        case .remove:
            return offset(atIndex: 0, layoutDown: layoutDown)
        case .copy:
            return offset(atIndex: 1, layoutDown: layoutDown)
        case .photo:
            return offset(atIndex: 2, layoutDown: layoutDown)
        case .resize:
            return offset(atIndex: 3, layoutDown: layoutDown)
        }
    }
    
    private func offset(atIndex index: Int, layoutDown: Bool) -> CGSize {
        let radius: CGFloat = 120
        let startAngleDeg = -180.0
        let step = 90.0 / Double(4 - 1)
        
        let angleDeg = startAngleDeg + (Double(index) * step)
        let angleRad = angleDeg * .pi / 180
        
        let x = cos(angleRad) * radius
        let y = sin(angleRad) * radius * (layoutDown ? -1 : 1)
        
        return CGSize(width: x, height: y)
    }
}

struct MapPinActionView: View, Equatable {
    let model: MapPinViewModel
    let pinId: UUID
    let layoutDown: Bool
    let pinSize: CGSize
    let isShown: Bool
    let borderColor: Color
    let canDrag: Bool
    let doubleTapAction: (() -> Void)?
    let dragEndAction: (() -> Void)?
    
    @Environment(MapRootModel.self) private var root
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif
    
    @Namespace private var glassNamespace
    @Namespace private var photoSpace
    
    @State private var showPhotoSelection: Bool = false
    @State private var selectedPhoto: ItemSelectionModel = ItemSelectionModel(isSingleSelection: true, allowCollections: false)
    
    // Equatable implementation: compare stable properties
    static func == (lhs: MapPinActionView, rhs: MapPinActionView) -> Bool {
        lhs.pinId == rhs.pinId &&
        lhs.layoutDown == rhs.layoutDown &&
        lhs.model.isExpandedId == rhs.model.isExpandedId &&
        lhs.pinSize == rhs.pinSize &&
        lhs.isShown == rhs.isShown &&
        lhs.borderColor == rhs.borderColor &&
        lhs.canDrag == rhs.canDrag &&
        lhs.model.pinPointer(for: lhs.pinId)?.location == rhs.model.pinPointer(for: rhs.pinId)?.location &&
        lhs.model.pinPointer(for: lhs.pinId)?.size == rhs.model.pinPointer(for: rhs.pinId)?.size &&
        lhs.model.pinPointer(for: lhs.pinId)?.photoId == rhs.model.pinPointer(for: rhs.pinId)?.photoId
    }
    
    var body: some View {
        MapPinView(model: model, pinId: pinId, pinSize: pinSize, isShown: isShown, borderColor: borderColor, canDrag: canDrag, doubleTapAction: doubleTapAction, dragEndAction: dragEndAction)
            .overlay {
#if os(visionOS)
                actionButtons
#else
                GlassEffectContainer {
                    actionButtons
                }
#endif
            }
            .sheet(isPresented: $showPhotoSelection) {
                root.viewController.photoSelection(root: root, selectionModel: selectedPhoto)
#if !os(macOS)
                    .navigationTransition(.zoom(sourceID: MapPinButtonType.photo.label, in: photoSpace))
#endif
            }
            .onChange(of: showPhotoSelection, initial: false) {
                guard !showPhotoSelection, !selectedPhoto.selection.isEmpty else { return }
                withAnimation { model.replacePhoto(pinId: pinId, itemId: selectedPhoto.itemId) }
                selectedPhoto.resetSelection(itemId: nil, entryId: nil)
            }
    }
    
    var actionButtons: some View {
        ZStack {
            button(type: .remove)
                .zIndex(10)
            button(type: .copy)
                .zIndex(10)
            button(type: .photo)
                .zIndex(10)
            button(type: .resize)
                .zIndex(10)

            
            Color.clear
#if !os(visionOS)
                .glassEffectID("menu", in: glassNamespace)
#endif
        }
    }
    
    private func button(type: MapPinButtonType) -> some View {
        return Button {
            switch type {
            case .remove:
                model.removePin(id: pinId)
            case .copy:
                model.copyPin(id: pinId)
            case .photo:
#if os(macOS)
            openWindow(id: NetworkModules.photo.linkWindowId)
#else
            showPhotoSelection.toggle()
#endif
            case .resize:
                model.resizePin(id: pinId)
            }
        } label: {
            Label(type.label, systemImage: type.systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 50, height: 50)
                .opacity(model.isExpandedId == pinId ? 1 : 0)
        }
        .borderLessTVBottonStyle()
        .foregroundStyle(.white)
#if !os(visionOS)
        .applyIf(model.isExpandedId == pinId) {
            $0.glassEffect(.regular.tint(NetworkModules.map.tint.opacity(0.75)).interactive())
        }
        .glassEffectID(type.label, in: glassNamespace)
#endif
        .offset(type.offset(expanded: model.isExpandedId != nil, layoutDown: layoutDown))
        .animation(.spring(duration: type.duration * 3, bounce: 0.2), value: model.isExpandedId == pinId)
        .opacity(model.isExpandedId == pinId ? 1 : 0)
        .matchedTransitionSource(id: type.label, in: photoSpace)
    }
}

#Preview(traits: .mockData) {
    @Previewable @State var id = UUID()
    @Previewable @State var model = MapPinViewModel(mapPins: [], pointer: .empty)
    ZStack {
        Color
            .blue
        
        MapPinActionView(model: model, pinId: id, layoutDown: true, pinSize: CGSize(width: 80, height: 80), isShown: true, borderColor: .red, canDrag: true) {
                print("double tap")
            } dragEndAction: {
                print("end move")
        }
        
    }
}
