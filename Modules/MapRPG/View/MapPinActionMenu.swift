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
        GlassEffectContainerAll {
            VStack(spacing: 8) {
                ForEach(context.actions, id: \.self) { type in
                    // The panel is glass already: flat buttons, no glass inside glass.
                    MapPinActionMenuButton(
                        model: model,
                        type: type,
                        context: context,
                        photoSpace: photoSpace
                    )
                }
            }
        }
        // Half of the default `padding()` inset.
        .padding(8)
        .modifier(
            MapPinPhotoSelectionModifier(
                model: model,
                context: context,
                photoSpace: photoSpace
            )
        )
    }
}

struct MapPinActionMenuButton: View {
    let model: MapPinNode
    let type: MapPinButtonType
    let context: MapPinActionContext
    let photoSpace: Namespace.ID

    private var pin: MapPinModel { model.pin }

    var body: some View {
        MapPopoverButton(
            title: Text(type.localizedLabel(for: pin)),
            systemImage: type.systemImage(for: pin),
            tint: type.tint(for: pin)
        ) {
            model.perform(type, context: context)
        }
        .applyIf(type == .photo) {
            $0.matchedTransitionSource(id: type.label, in: photoSpace)
        }
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
