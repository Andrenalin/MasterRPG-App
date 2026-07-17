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
    let model: MapPinViewModel
    let pin: MapPinModel
    let isExpanded: Bool
    let layoutDown: Bool
    let pinSize: CGSize
    let canDrag: Bool
    let actionContext: MapPinActionContext
    let doubleTapAccessibilityLabel: LocalizedStringResource
    var usesGlassEffects: Bool = true
    let doubleTapAction: (() -> Void)?
    let dragEndAction: ((MapPinModel) -> Void)?
    var tapAction: (() -> Void)? = nil
    var onToggleDead: (() -> Void)? = nil
    var onToggleVisibility: (() -> Void)? = nil
    var onResize: (() -> Void)? = nil
    var onToggleZoom: (() -> Void)? = nil

    @GestureState private var dragTranslation: CGSize = .zero

    var body: some View {
        MapPinView(
            pin: pin,
            pinSize: pinSize,
            canMove: canDrag,
            doubleTapAccessibilityLabel: doubleTapAccessibilityLabel,
            doubleTapAction: doubleTapAction,
            moveAction: moveAccessibility,
            tapAction: handleTap
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
                if isExpanded, actionContext != .none {
                    MapPinExpandedMenu(
                        model: model,
                        pin: pin,
                        layoutDown: layoutDown,
                        context: actionContext,
                        usesGlassEffects: usesGlassEffects,
                        onToggleDead: onToggleDead,
                        onToggleVisibility: onToggleVisibility,
                        onResize: onResize,
                        onToggleZoom: onToggleZoom
                    )
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .offset(dragTranslation)
    }

    private func handleTap() {
        if actionContext != .none {
            model.isExpandedId = isExpanded ? nil : pin.id
        }
        tapAction?()
    }

    private func moveAccessibility(_ translation: CGSize) {
        commitMove(translation: translation)
    }

    private func commitMove(translation: CGSize) {
        guard canDrag, translation != .zero else { return }
        var updatedPin = pin
        updatedPin.location = CGPoint(
            x: pin.location.x + translation.width,
            y: pin.location.y + translation.height
        )
        updatedPin.timeInterval = max(
            Date.now.timeIntervalSince1970,
            pin.timeInterval.nextUp
        )
        dragEndAction?(updatedPin)
    }

#if !os(tvOS)
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .updating($dragTranslation) { value, state, _ in
                guard canDrag else { return }
                state = value.translation
            }
            .onEnded { value in
                commitMove(translation: value.translation)
            }
    }
#endif
}

private struct MapPinExpandedMenu: View {
    let model: MapPinViewModel
    let pin: MapPinModel
    let layoutDown: Bool
    let context: MapPinActionContext
    let usesGlassEffects: Bool
    let onToggleDead: (() -> Void)?
    let onToggleVisibility: (() -> Void)?
    let onResize: (() -> Void)?
    let onToggleZoom: (() -> Void)?

    @Environment(MapRootModel.self) private var root
    @Environment(ScenesManager.self) private var scenesManager

    @Namespace private var glassNamespace
    @Namespace private var photoSpace

    @State private var showPhotoSelection = false
    @State private var selectedPhoto = ItemSelectionModel(isSingleSelection: true, allowCollections: false)

    var body: some View {
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
        .sheet(isPresented: context == .editor ? $showPhotoSelection : .constant(false)) {
            ManagedPresentationView {
                root.viewController.photoSelection(root: root, selectionModel: selectedPhoto)
#if !os(macOS)
                    .navigationTransition(.zoom(sourceID: MapPinButtonType.photo.label, in: photoSpace))
#endif
            }
        }
        .onChange(of: showPhotoSelection) {
            guard context == .editor,
                  !showPhotoSelection,
                  !selectedPhoto.selection.isEmpty else { return }
            withAnimation { model.replacePhoto(pinId: pin.id, itemId: selectedPhoto.itemId) }
            selectedPhoto.resetSelection(itemId: nil, entryId: nil)
        }
    }

    private var actionButtons: some View {
        MapPinActionButtons(
            pin: pin,
            isExpanded: true,
            layoutDown: layoutDown,
            context: context,
            glassNamespace: glassNamespace,
            photoSpace: photoSpace,
            usesGlassEffects: usesGlassEffects,
            action: performAction
        )
    }

    private func performAction(_ type: MapPinButtonType) {
        switch type {
        case .remove:
            model.removePin(id: pin.id)
        case .copy:
            model.copyPin(id: pin.id)
        case .photo:
#if os(macOS)
            scenesManager.openWindow(SceneId(rawValue: NetworkModules.photo.linkWindowId))
#else
            showPhotoSelection.toggle()
#endif
        case .resize:
            if context == .editor {
                model.resizePin(id: pin.id)
            } else {
                onResize?()
            }
        case .dead:
            if context == .editor {
                model.toggleDeadPin(id: pin.id)
            } else {
                onToggleDead?()
            }
        case .visibility:
            onToggleVisibility?()
        case .zoom:
            onToggleZoom?()
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @State var id = UUID()
    @Previewable @State var model = MapPinViewModel(mapPins: [], pointer: .empty)
    ZStack {
        Color.blue
        MapPinActionView(
            model: model,
            pin: .empty(id),
            isExpanded: true,
            layoutDown: true,
            pinSize: CGSize(width: 80, height: 80),
            canDrag: true,
            actionContext: .editor,
            doubleTapAccessibilityLabel: LocalizedStringResource("Toggle Player Visibility", bundle: .module)
        ) {
            print("double tap")
        } dragEndAction: { _ in
            print("end move")
        }
    }
}
