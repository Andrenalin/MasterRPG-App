// @copyright André Trettin

import CharacterRPG
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

    @Environment(MapRootModel.self) private var root
    @Namespace private var photoSpace

    /// The context's actions; "Add Pin to Battle Round" only while a battle runs on this map and
    /// the pin has no turn yet.
    private var actions: [MapPinButtonType] {
        let battleRound = root.mapGameControllable.battleRoundModel
        let canJoinBattle = battleRound.canJoinBattle(
            pinId: model.pin.id,
            on: root.gameController.gameModel.currentItemId
        )
        return context.actions.filter { $0 != .battle || canJoinBattle }
    }

    var body: some View {
        // No glass container: the panel is glass already and the buttons are flat (no glass inside
        // glass), so a container around them had no glass children and did nothing.
        // See CODE_AUDIT_21 §8.4.
        VStack(spacing: MapPopoverLayout.contentInset) {
            ForEach(actions, id: \.self) { type in
                MapPinActionMenuButton(pin: model.pin, type: type) {
                    model.perform(type, context: context)
                }
                .applyIf(type == .photo || type == .character) {
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
        .modifier(
            MapPinCharacterSelectionModifier(
                model: model,
                context: context,
                characterSpace: photoSpace
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

/// Presents the character picker for the editor's "Choose Pin Character" action and
/// writes the selection back into the pin's `characterId`.
struct MapPinCharacterSelectionModifier: ViewModifier {
    let model: MapPinNode
    let context: MapPinActionContext
    let characterSpace: Namespace.ID

    @Environment(MapRootModel.self) private var root
#if os(macOS)
    @Environment(ScenesManager.self) private var scenesManager
#endif

    @State private var selectedCharacter = ItemSelectionModel(isSingleSelection: true, allowCollections: false)

    func body(content: Content) -> some View {
        @Bindable var model = model

        content
#if os(macOS)
            .onChange(of: model.isCharacterSelectionPresented) { _, isPresented in
                guard context == .editor, isPresented else { return }
                root.characterRoot.itemSelectionModel = selectedCharacter
                scenesManager.openWindow(SceneId(rawValue: NetworkModules.value.linkWindowId))
                model.isCharacterSelectionPresented = false
            }
            .onChange(of: selectedCharacter.selection) {
                guard context == .editor, let itemId = selectedCharacter.itemId else { return }
                withAnimation { model.replaceCharacter(with: itemId) }
                selectedCharacter.resetSelection(itemId: nil, entryId: nil)
            }
#else
            .sheet(isPresented: context == .editor ? $model.isCharacterSelectionPresented : .constant(false)) {
                ManagedPresentationView {
                    root.viewController.characterSelection(root: root, selectionModel: selectedCharacter)
                        .navigationTransition(.zoom(sourceID: MapPinButtonType.character.label, in: characterSpace))
                }
            }
            .onChange(of: model.isCharacterSelectionPresented) {
                guard context == .editor,
                      !model.isCharacterSelectionPresented,
                      !selectedCharacter.selection.isEmpty else { return }
                withAnimation { model.replaceCharacter(with: selectedCharacter.itemId) }
                selectedCharacter.resetSelection(itemId: nil, entryId: nil)
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
