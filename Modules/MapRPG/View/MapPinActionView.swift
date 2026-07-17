// @copyright André Trettin

import CoreRPG
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

    func offset(at index: Int, count: Int, expanded: Bool, layoutDown: Bool) -> CGSize {
        guard expanded else { return .zero }
        let radius: CGFloat = 120
        let divisor = max(1, count - 1)
        let angleDeg = -180.0 + Double(index) * (90.0 / Double(divisor))
        let angleRad = angleDeg * .pi / 180
        return CGSize(
            width: cos(angleRad) * radius,
            height: sin(angleRad) * radius * (layoutDown ? -1 : 1)
        )
    }
}

struct MapPinActionView: View {
    let model: MapPinNode
    let layoutDown: Bool
    let pinScale: CGFloat
    let canDrag: Bool
    let actionContext: MapPinActionContext
    let doubleTapAccessibilityLabel: LocalizedStringResource
    var usesGlassEffects: Bool = true

    @GestureState private var dragTranslation: CGSize = .zero

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
            .overlay {
                if model.isExpanded, actionContext != .none {
                    MapPinExpandedMenu(
                        model: model,
                        layoutDown: layoutDown,
                        context: actionContext,
                        usesGlassEffects: usesGlassEffects
                    )
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .offset(dragTranslation)
            .offset(x: location.x, y: location.y)
    }

#if !os(tvOS)
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .updating($dragTranslation) { value, state, _ in
                guard canDrag else { return }
                state = value.translation
            }
            .onChanged { _ in
                guard canDrag else { return }
                model.beginMove()
            }
            .onEnded { value in
                guard canDrag else { return }
                model.move(by: value.translation)
            }
    }
#endif
}

private struct MapPinExpandedMenu: View {
    let model: MapPinNode
    let layoutDown: Bool
    let context: MapPinActionContext
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
            scenesManager.openWindow(SceneId(rawValue: NetworkModules.photo.linkWindowId))
            model.isPhotoSelectionPresented = false
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
    }

    private var actionButtons: some View {
        MapPinActionButtons(
            model: model,
            layoutDown: layoutDown,
            context: context,
            glassNamespace: glassNamespace,
            photoSpace: photoSpace,
            usesGlassEffects: usesGlassEffects
        )
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
            layoutDown: true,
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
