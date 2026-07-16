// @copyright André Trettin

import CoreRPG
import SwiftUI

enum MapPinButtonType: String {
    case remove, copy, photo, resize

    var systemImage: String {
        switch self {
        case .remove: return "trash"
        case .copy:   return "document.on.document"
        case .photo:  return "photo"
        case .resize: return "square.resize"
        }
    }

    var label: String { rawValue.capitalized }

    var localizedLabel: LocalizedStringResource {
        switch self {
        case .remove: LocalizedStringResource("Remove Pin", bundle: .module)
        case .copy: LocalizedStringResource("Copy Pin", bundle: .module)
        case .photo: LocalizedStringResource("Choose Pin Photo", bundle: .module)
        case .resize: LocalizedStringResource("Resize Pin", bundle: .module)
        }
    }

    var duration: CGFloat {
        switch self {
        case .remove: return 0.3
        case .copy:   return 0.4
        case .photo:  return 0.5
        case .resize: return 0.6
        }
    }

    func offset(expanded: Bool, layoutDown: Bool) -> CGSize {
        guard expanded else { return .zero }
        switch self {
        case .remove: return offset(atIndex: 0, layoutDown: layoutDown)
        case .copy:   return offset(atIndex: 1, layoutDown: layoutDown)
        case .photo:  return offset(atIndex: 2, layoutDown: layoutDown)
        case .resize: return offset(atIndex: 3, layoutDown: layoutDown)
        }
    }

    private func offset(atIndex index: Int, layoutDown: Bool) -> CGSize {
        let radius: CGFloat = 120
        let angleDeg = -180.0 + Double(index) * (90.0 / 3.0)
        let angleRad = angleDeg * .pi / 180
        return CGSize(
            width: cos(angleRad) * radius,
            height: sin(angleRad) * radius * (layoutDown ? -1 : 1)
        )
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
    let showActions: Bool
    let doubleTapAction: (() -> Void)?
    let dragEndAction: (() -> Void)?

    @Environment(MapRootModel.self) private var root
    @Environment(ScenesManager.self) private var scenesManager

    @Namespace private var glassNamespace
    @Namespace private var photoSpace

    @State private var showPhotoSelection: Bool = false
    @State private var selectedPhoto: ItemSelectionModel = ItemSelectionModel(isSingleSelection: true, allowCollections: false)

    // Resolve pointer once — avoids 6 linear scans in ==
    static func == (lhs: MapPinActionView, rhs: MapPinActionView) -> Bool {
        guard lhs.pinId == rhs.pinId,
              lhs.layoutDown == rhs.layoutDown,
              lhs.model.isExpandedId == rhs.model.isExpandedId,
              lhs.pinSize == rhs.pinSize,
              lhs.isShown == rhs.isShown,
              lhs.borderColor == rhs.borderColor,
              lhs.canDrag == rhs.canDrag,
              lhs.showActions == rhs.showActions else { return false }
        let lp = lhs.model.pinPointer(for: lhs.pinId)
        let rp = rhs.model.pinPointer(for: rhs.pinId)
        return lp?.location == rp?.location
            && lp?.size == rp?.size
            && lp?.photoId == rp?.photoId
    }

    var body: some View {
        MapPinView(model: model, pinId: pinId, pinSize: pinSize, isShown: isShown, borderColor: borderColor, canDrag: canDrag, doubleTapAction: doubleTapAction, dragEndAction: dragEndAction)
            .overlay {
                if showActions {
#if os(visionOS)
                    actionButtons
#else
                    GlassEffectContainer {
                        actionButtons
                    }
#endif
                }
            }
            .sheet(isPresented: showActions ? $showPhotoSelection : .constant(false)) {
                ManagedPresentationView {
                    root.viewController.photoSelection(root: root, selectionModel: selectedPhoto)
#if !os(macOS)
                        .navigationTransition(.zoom(sourceID: MapPinButtonType.photo.label, in: photoSpace))
#endif
                }
            }
            .onChange(of: showPhotoSelection) {
                guard showActions, !showPhotoSelection, !selectedPhoto.selection.isEmpty else { return }
                withAnimation { model.replacePhoto(pinId: pinId, itemId: selectedPhoto.itemId) }
                selectedPhoto.resetSelection(itemId: nil, entryId: nil)
            }
    }

    // Extracted subview — SwiftUI can skip re-evaluation when inputs are unchanged
    private var actionButtons: some View {
        MapPinActionButtons(
            model: model,
            pinId: pinId,
            layoutDown: layoutDown,
            glassNamespace: glassNamespace,
            photoSpace: photoSpace,
            onRemove: { model.removePin(id: pinId) },
            onCopy: { model.copyPin(id: pinId) },
            onResize: { model.resizePin(id: pinId) },
            onPhoto: {
#if os(macOS)
                scenesManager.openWindow(SceneId(rawValue: NetworkModules.photo.linkWindowId))
#else
                showPhotoSelection.toggle()
#endif
            }
        )
    }
}

#Preview(traits: .mockData) {
    @Previewable @State var id = UUID()
    @Previewable @State var model = MapPinViewModel(mapPins: [], pointer: .empty)
    ZStack {
        Color.blue
        MapPinActionView(model: model, pinId: id, layoutDown: true, pinSize: CGSize(width: 80, height: 80), isShown: true, borderColor: .red, canDrag: true, showActions: true) {
            print("double tap")
        } dragEndAction: {
            print("end move")
        }
    }
}
