// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Adds monster or photo pins to the game's currently focused room. Shared by the 2D
/// map toolbar (`GameToolBar`) and the 3D table toolbar so both offer the
/// same picker sheet and pin-drop behavior — only what happens *after* the
/// pins land differs per renderer (2D pushes an update only while its "Share
/// Map" toggle is on; the 3D table always re-syncs its pawns and broadcasts),
/// so callers supply that as `onMonstersAdded`.
struct ChooseMapPinsButton: View {
    @ScaledMetric private var iconSize: CGFloat = 24
    let root: MapRootModel
    let focusedRoomId: UUID?
    /// Without a focused room, new pins go to the middle of the map instead of staying
    /// unpositioned. See `GameToolBarSession.placesNewPinsInMapCenter`.
    var placesInMapCenter: Bool = false
    let onMonstersAdded: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ScenesManager.self) private var scenesManager

    @State private var showPinSelection: Bool = false
    @State private var showPhotoPinSelection: Bool = false
    @State private var selectedPin: ItemSelectionModel = ItemSelectionModel(isSingleSelection: false, allowCollections: true)
    @State private var selectedPhotoPin: ItemSelectionModel = ItemSelectionModel(isSingleSelection: false, allowCollections: false)
    @Namespace private var pinSpace

    var body: some View {
        Menu {
            Button(
                String(localized: "Character Pins", bundle: .module),
                systemImage: NetworkModules.value.icon
            ) {
#if os(macOS)
                scenesManager.openWindow(SceneId(rawValue: NetworkModules.value.linkWindowId))
#else
                showPinSelection.toggle()
#endif
            }
            Button(
                String(localized: "Photo Pins", bundle: .module),
                systemImage: NetworkModules.photo.icon
            ) {
#if os(macOS)
                root.photoRoot.itemSelectionModel = selectedPhotoPin
                scenesManager.openWindow(SceneId(rawValue: NetworkModules.photo.linkWindowId))
#else
                showPhotoPinSelection.toggle()
#endif
            }
        } label: {
            let symbolName = "mappin\(showPinSelection || showPhotoPinSelection ? ".and.ellipse" : "")"
            Image(systemName: symbolName)
                .contentTransition(.symbolEffect(.replace.wholeSymbol))
                .frame(width: iconSize, height: iconSize)
        }
        .selectedRoundButton(
            title: String(localized: "Choose Map Pins", bundle: .module),
            module: .map,
            isSelected: false
        )
        .matchedTransitionSource(id: "gamePin", in: pinSpace)
        .sheet(isPresented: $showPinSelection) {
            ManagedPresentationView {
                root.viewController.characterSelection(root: root, selectionModel: selectedPin)
#if !os(macOS)
                    .navigationTransition(.zoom(sourceID: "gamePin", in: pinSpace))
#endif
            }
        }
        .sheet(isPresented: $showPhotoPinSelection) {
            ManagedPresentationView {
                root.viewController.photoSelection(root: root, selectionModel: selectedPhotoPin)
            }
        }
        .onChange(of: showPinSelection, initial: false) { _, newValue in
            guard !newValue, !selectedPin.selection.isEmpty else { return }
            let map = root.gameController.currentItem()
            let monsters = selectedPin.selection.map { ItemRowModel(itemId: $0.itemId, typeId: .value) }
            withAnimation(reduceMotion ? nil : .bouncy) {
                root.editController.addMonsters(
                    map: map,
                    entryId: focusedRoomId,
                    location: nil,
                    monsters: monsters,
                    number: 1,
                    placesInMapCenter: placesInMapCenter
                )
            }
            onMonstersAdded()
            selectedPin.resetSelection(itemId: nil, entryId: nil)
        }
        // Photo pins: the sheet closing on iOS/visionOS, every pick in the macOS window.
#if os(macOS)
        .onChange(of: selectedPhotoPin.selection, initial: false) {
            addSelectedPhotoPins()
        }
#else
        .onChange(of: showPhotoPinSelection, initial: false) { _, isPresented in
            guard !isPresented else { return }
            addSelectedPhotoPins()
        }
#endif
    }

    private func addSelectedPhotoPins() {
        let photoIds = selectedPhotoPin.selection.map(\.itemId)
        guard !photoIds.isEmpty else { return }
        let map = root.gameController.currentItem()
        withAnimation(reduceMotion ? nil : .bouncy) {
            root.editController.addPhotoPins(
                map: map,
                entryId: focusedRoomId,
                location: nil,
                photoIds: photoIds,
                placesInMapCenter: placesInMapCenter
            )
        }
        onMonstersAdded()
        selectedPhotoPin.resetSelection(itemId: nil, entryId: nil)
    }
}

#Preview {
    ChooseMapPinsButton(root: .preview, focusedRoomId: nil, onMonstersAdded: {})
        .environment(ScenesManager())
}
