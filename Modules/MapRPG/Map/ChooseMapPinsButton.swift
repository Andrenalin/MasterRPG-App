// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Adds monster pins to the game's currently focused room. Shared by the 2D
/// map toolbar (`GameToolBar`) and the 3D table toolbar so both offer the
/// same picker sheet and pin-drop behavior — only what happens *after* the
/// pins land differs per renderer (2D pushes an update only while its "Share
/// Map" toggle is on; the 3D table always re-syncs its pawns and broadcasts),
/// so callers supply that as `onMonstersAdded`.
struct ChooseMapPinsButton: View {
    let root: MapRootModel
    let focusedRoomId: UUID?
    let onMonstersAdded: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ScenesManager.self) private var scenesManager

    @State private var showPinSelection: Bool = false
    @State private var selectedPin: ItemSelectionModel = ItemSelectionModel(isSingleSelection: false, allowCollections: true)
    @Namespace private var pinSpace

    var body: some View {
        Button {
#if os(macOS)
            scenesManager.openWindow(SceneId(rawValue: NetworkModules.value.linkWindowId))
#else
            showPinSelection.toggle()
#endif
        } label: {
            let symbolName = "mappin\(showPinSelection ? ".and.ellipse" : "")"
            Image(systemName: symbolName)
                .contentTransition(.symbolEffect(.replace.wholeSymbol))
                .frame(width: 24, height: 24)
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
                    number: 1
                )
            }
            onMonstersAdded()
            selectedPin.resetSelection(itemId: nil, entryId: nil)
        }
    }
}

/// Cross-module entry point: `EditController`/`characterSelection` are internal
/// to MapRPG, so other modules (GameRPG's 3D table toolbar) reach
/// `ChooseMapPinsButton` through this instead of constructing it directly.
public extension ViewController {
    @MainActor @ViewBuilder
    func choosePinsButton(
        root: MapRootModel,
        focusedRoomId: UUID?,
        onMonstersAdded: @escaping () -> Void
    ) -> some View {
        ChooseMapPinsButton(root: root, focusedRoomId: focusedRoomId, onMonstersAdded: onMonstersAdded)
    }
}

#Preview {
    ChooseMapPinsButton(root: .preview, focusedRoomId: nil, onMonstersAdded: {})
        .environment(ScenesManager())
}
