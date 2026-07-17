// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

enum MapPinActionContext: Equatable {
    case none
    case editor
    case gameMaster

    var actions: [MapPinButtonType] {
        switch self {
        case .none:
            []
        case .editor:
            [.remove, .copy, .photo, .resize, .dead]
        case .gameMaster:
            [.dead, .visibility, .resize, .zoom]
        }
    }
}

enum MapPinButtonType: String, Hashable {
    case remove, copy, photo, resize, dead, visibility, zoom

    func systemImage(for pin: MapPinModel) -> String {
        switch self {
        case .remove: return "trash"
        case .copy:   return "document.on.document"
        case .photo:  return "photo"
        case .resize: return "square.resize"
        case .dead: return pin.isDead ? "heart.fill" : "xmark.circle"
        case .visibility: return pin.isShown ? "eye.slash" : "eye"
        case .zoom: return pin.isZoom ? "minus.magnifyingglass" : "plus.magnifyingglass"
        }
    }

    var label: String { rawValue.capitalized }

    func tint(for pin: MapPinModel) -> Color {
        switch self {
        case .remove: .red
        case .copy: .gray
        case .photo: .purple
        case .resize: .teal
        case .visibility: .blue
        case .zoom: .indigo
        case .dead: pin.isDead ? .green : .red
        }
    }

    func localizedLabel(for pin: MapPinModel) -> LocalizedStringResource {
        switch self {
        case .remove: LocalizedStringResource("Remove Pin", bundle: .module)
        case .copy: LocalizedStringResource("Copy Pin", bundle: .module)
        case .photo: LocalizedStringResource("Choose Pin Photo", bundle: .module)
        case .resize: LocalizedStringResource("Resize Pin", bundle: .module)
        case .dead:
            pin.isDead
                ? LocalizedStringResource("Revive Pin", bundle: .module)
                : LocalizedStringResource("Mark Pin Dead", bundle: .module)
        case .visibility:
            pin.isShown
                ? LocalizedStringResource("Hide Pin", bundle: .module)
                : LocalizedStringResource("Show Pin", bundle: .module)
        case .zoom:
            pin.isZoom
                ? LocalizedStringResource("Reset Pin Zoom", bundle: .module)
                : LocalizedStringResource("Zoom Pin", bundle: .module)
        }
    }

}

struct MapPinActionView: View {
    let model: MapPinNode
    let pinScale: CGFloat
    let canDrag: Bool
    let actionContext: MapPinActionContext
    let doubleTapAccessibilityLabel: LocalizedStringResource
    var usesGlassEffects: Bool = true
    var viewportScale: CGFloat = 1

    @GestureState private var dragTranslation: CGSize = .zero
    @State private var isMoving = false

    private var pin: MapPinModel { model.pin }

    private var pinSize: CGSize {
        let zoomScale: CGFloat = pin.isZoom ? 4 : 1
        return pin.size.size * pinScale * zoomScale
    }

    private var location: CGPoint {
        pin.location - (pinSize / 2)
    }

    var body: some View {
        MapPinView(
            model: model,
            pinSize: pinSize,
            canMove: canDrag,
            actionContext: actionContext,
            doubleTapAccessibilityLabel: doubleTapAccessibilityLabel
        )
#if !os(tvOS)
            // Keep the drag recognizer on the pin itself. Attaching it after
            // the overlay made slight movement on an expanded action button
            // drag the token as well.
            .highPriorityGesture(
                dragGesture,
                including: canDrag ? .all : .none
            )
#endif
            .offset(logicalTranslation(dragTranslation))
            .offset(x: location.x, y: location.y)
    }

#if !os(tvOS)
    private var dragGesture: some Gesture {
        DragGesture(
            minimumDistance: 3,
            coordinateSpace: .named(MapViewportCoordinateSpace.name)
        )
            .updating($dragTranslation) { value, state, _ in
                guard canDrag else { return }
                state = value.translation
            }
            .onChanged { _ in
                guard canDrag, !isMoving else { return }
                isMoving = true
                model.beginMove()
            }
            .onEnded { value in
                guard canDrag else { return }
                isMoving = false
                model.move(by: logicalTranslation(value.translation))
            }
    }

#endif

    private func logicalTranslation(_ translation: CGSize) -> CGSize {
        let scale = viewportScale.isFinite && viewportScale > 0 ? viewportScale : 1
        return CGSize(width: translation.width / scale, height: translation.height / scale)
    }
}

struct MapPinExpandedMenu: View {
    let model: MapPinNode
    let context: MapPinActionContext
    let placement: MapAdaptiveFanPlacement
    let usesGlassEffects: Bool

    @Environment(MapRootModel.self) private var root
#if os(macOS)
    @Environment(ScenesManager.self) private var scenesManager
#endif

    @Namespace private var glassNamespace
    @Namespace private var photoSpace

    @State private var selectedPhoto = ItemSelectionModel(isSingleSelection: true, allowCollections: false)

    var body: some View {
        @Bindable var model = model

        Group {
#if os(visionOS)
            actionButtons
#else
            if usesGlassEffects {
                GlassEffectContainer {
                    actionButtons
                }
            } else {
                actionButtons
            }
#endif
        }
#if os(macOS)
        .onChange(of: model.isPhotoSelectionPresented) { _, isPresented in
            guard context == .editor, isPresented else { return }
            root.photoRoot.itemSelectionModel = selectedPhoto
            scenesManager.openWindow(SceneId(rawValue: NetworkModules.photo.linkWindowId))
            model.isPhotoSelectionPresented = false
        }
        .onChange(of: selectedPhoto.selection) {
            guard context == .editor, let itemId = selectedPhoto.itemId else { return }
            withAnimation { model.replacePhoto(with: itemId) }
            selectedPhoto.resetSelection(itemId: nil, entryId: nil)
        }
#else
        .sheet(isPresented: context == .editor ? $model.isPhotoSelectionPresented : .constant(false)) {
            ManagedPresentationView {
                root.viewController.photoSelection(root: root, selectionModel: selectedPhoto)
                    .navigationTransition(.zoom(sourceID: MapPinButtonType.photo.label, in: photoSpace))
            }
        }
        .onChange(of: model.isPhotoSelectionPresented) {
            guard context == .editor,
                  !model.isPhotoSelectionPresented,
                  !selectedPhoto.selection.isEmpty else { return }
            withAnimation { model.replacePhoto(with: selectedPhoto.itemId) }
            selectedPhoto.resetSelection(itemId: nil, entryId: nil)
        }
#endif
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var actionButtons: some View {
        MapPinActionButtons(
            model: model,
            context: context,
            placement: placement,
            glassNamespace: glassNamespace,
            photoSpace: photoSpace,
            usesGlassEffects: usesGlassEffects
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview(traits: .mockData) {
    @Previewable @State var model = MapPinViewModel(
        mapPins: [.empty(MapModel.previewId)],
        pointer: .empty
    )
    ZStack {
        Color.blue
        MapPinActionView(
            model: model.mapPinNodes[0],
            pinScale: 1,
            canDrag: true,
            actionContext: .editor,
            doubleTapAccessibilityLabel: LocalizedStringResource("Toggle Player Visibility", bundle: .module)
        )
    }
    .onAppear {
        model.isExpandedId = MapModel.previewId
    }
}
