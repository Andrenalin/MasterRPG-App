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

struct MapPinActionView: View, Equatable {
    let model: MapPinViewModel
    let pin: MapPinModel
    let layoutDown: Bool
    let pinSize: CGSize
    let canDrag: Bool
    let actionContext: MapPinActionContext
    let doubleTapAccessibilityLabel: LocalizedStringResource
    var usesGlassEffects: Bool = true
    let doubleTapAction: (() -> Void)?
    let dragEndAction: (() -> Void)?
    var tapAction: (() -> Void)? = nil
    var onToggleDead: (() -> Void)? = nil
    var onToggleVisibility: (() -> Void)? = nil
    var onResize: (() -> Void)? = nil
    var onToggleZoom: (() -> Void)? = nil

    @Environment(MapRootModel.self) private var root
    @Environment(ScenesManager.self) private var scenesManager

    @Namespace private var glassNamespace
    @Namespace private var photoSpace

    @State private var showPhotoSelection: Bool = false
    @State private var selectedPhoto: ItemSelectionModel = ItemSelectionModel(isSingleSelection: true, allowCollections: false)

    // Resolve pointer once — avoids 6 linear scans in ==
    static func == (lhs: MapPinActionView, rhs: MapPinActionView) -> Bool {
        lhs.pin == rhs.pin
            && lhs.layoutDown == rhs.layoutDown
            && lhs.model.isExpandedId == rhs.model.isExpandedId
            && lhs.pinSize == rhs.pinSize
            && lhs.canDrag == rhs.canDrag
            && lhs.actionContext == rhs.actionContext
            && lhs.usesGlassEffects == rhs.usesGlassEffects
            && lhs.doubleTapAccessibilityLabel == rhs.doubleTapAccessibilityLabel
    }

    var body: some View {
        MapPinView(
            model: model,
            pin: pin,
            pinSize: pinSize,
            canDrag: canDrag,
            opensActionMenu: actionContext != .none,
            doubleTapAccessibilityLabel: doubleTapAccessibilityLabel,
            doubleTapAction: doubleTapAction,
            dragEndAction: dragEndAction,
            tapAction: tapAction
        )
            .overlay {
                if actionContext != .none {
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
            }
            .sheet(isPresented: actionContext == .editor ? $showPhotoSelection : .constant(false)) {
                ManagedPresentationView {
                    root.viewController.photoSelection(root: root, selectionModel: selectedPhoto)
#if !os(macOS)
                        .navigationTransition(.zoom(sourceID: MapPinButtonType.photo.label, in: photoSpace))
#endif
                }
            }
            .onChange(of: showPhotoSelection) {
                guard actionContext == .editor,
                      !showPhotoSelection,
                      !selectedPhoto.selection.isEmpty else { return }
                withAnimation { model.replacePhoto(pinId: pin.id, itemId: selectedPhoto.itemId) }
                selectedPhoto.resetSelection(itemId: nil, entryId: nil)
            }
    }

    // Extracted subview — SwiftUI can skip re-evaluation when inputs are unchanged
    private var actionButtons: some View {
        MapPinActionButtons(
            model: model,
            pin: pin,
            layoutDown: layoutDown,
            context: actionContext,
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
            if actionContext == .editor {
                model.resizePin(id: pin.id)
            } else {
                onResize?()
            }
        case .dead:
            if actionContext == .editor {
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
            layoutDown: true,
            pinSize: CGSize(width: 80, height: 80),
            canDrag: true,
            actionContext: .editor,
            doubleTapAccessibilityLabel: LocalizedStringResource("Toggle Player Visibility", bundle: .module)
        ) {
            print("double tap")
        } dragEndAction: {
            print("end move")
        }
    }
}
