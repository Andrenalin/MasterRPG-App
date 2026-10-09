// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

// Pin action menu in the style of the game master's side menu
// (`MasterModuleWindowMenu`): circular buttons in a `MapPopover` panel
// pointing at the pin, on every platform. The actions are the same as
// `MapPinActionContext.actions`.

/// A vertical column of pin action buttons, laid out like the master side menu.
struct MapPinActionMenuStack: View {
    let model: MapPinNode
    let context: MapPinActionContext

    @Namespace private var photoSpace

    var body: some View {
        // No glass container: the panel is glass already and the buttons are flat (no glass inside
        // glass), so a container around them had no glass children and did nothing.
        // See CODE_AUDIT_21 §8.4.
        VStack(spacing: MapPopoverLayout.contentInset) {
            ForEach(context.actions, id: \.self) { type in
                MapPinActionMenuButton(pin: model.pin, type: type) {
                    model.perform(type, context: context)
                }
                .applyIf(type == .photo) {
                    $0.matchedTransitionSource(id: type.label, in: photoSpace)
                }
            }
        }
        .padding(MapPopoverLayout.contentInset)
        .modifier(
            MapPinPhotoSelectionModifier(
                model: model,
                context: context,
                photoSpace: photoSpace
            )
        )
    }
}

/// The game master's pin actions for a map surface without a `MapPinNode`: GameRPG's 3D
/// table, which performs the actions itself. A column next to the pin on the camera-based
/// table, a row above it in the visionOS volume.
struct MapPinGameActionMenu: View {
    let pin: MapPinModel
    let actions: [MapPinButtonType]
    let axis: Axis
    let perform: @MainActor (MapPinButtonType) -> Void

    private var layout: AnyLayout {
        axis == .vertical
            ? AnyLayout(VStackLayout(spacing: MapPopoverLayout.contentInset))
            : AnyLayout(HStackLayout(spacing: MapPopoverLayout.contentInset))
    }

    var body: some View {
        layout {
            ForEach(actions, id: \.self) { type in
                MapPinActionMenuButton(pin: pin, type: type) {
                    perform(type)
                }
            }
        }
        .padding(MapPopoverLayout.contentInset)
    }
}

struct MapPinActionMenuButton: View {
    let pin: MapPinModel
    let type: MapPinButtonType
    let action: () -> Void

    var body: some View {
        MapPopoverButton(
            title: Text(type.localizedLabel(for: pin)),
            systemImage: type.systemImage(for: pin),
            tint: type.tint(for: pin),
            action: action
        )
    }
}

/// Presents the photo picker for the editor's "Choose Pin Photo" action and
/// writes the selection back into the pin.
struct MapPinPhotoSelectionModifier: ViewModifier {
    let model: MapPinNode
    let context: MapPinActionContext
    let photoSpace: Namespace.ID

    @Environment(MapRootModel.self) private var root
#if os(macOS)
    @Environment(ScenesManager.self) private var scenesManager
#endif

    @State private var selectedPhoto = ItemSelectionModel(isSingleSelection: true, allowCollections: false)

    func body(content: Content) -> some View {
        @Bindable var model = model

        content
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
    }
}

#Preview("Pin Action Menu", traits: .mockData) {
    @Previewable @State var model = MapPinViewModel(
        mapPins: [.empty(MapModel.previewId)],
        pointer: .empty
    )
    HStack(alignment: .top) {
        MapPinActionMenuStack(model: model.mapPinNodes[0], context: .editor)
        MapPinActionMenuStack(model: model.mapPinNodes[0], context: .gameMaster)
    }
    .background(Color.blue.gradient)
}

#Preview("Game Table Pin Actions") {
    let pin = MapPinModel.empty(MapModel.previewId)
    VStack {
        MapPinGameActionMenu(pin: pin, actions: MapPinActionContext.gameMaster.actions, axis: .horizontal) { _ in }
        MapPinGameActionMenu(pin: pin, actions: MapPinActionContext.gameMaster.actions, axis: .vertical) { _ in }
    }
    .background(Color.blue.gradient)
}
