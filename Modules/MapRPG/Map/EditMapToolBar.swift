// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI
import CharacterRPG

struct EditToolBarViewModifier: ViewModifier {
    let mapEditController: MapEditController
    let editorModel: MapEditorSession
    let isTileEditor: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.networkActions) private var networkActions
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(MapRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var exitReady: Bool = false
    @State private var hideScales: Bool = true
    @State private var showPinSelection: Bool = false

    @State private var selectedPin: ItemSelectionModel = ItemSelectionModel(isSingleSelection: false, allowCollections: true)

    @Namespace private var pinSpace

    @ViewBuilder
    func body(content: Content) -> some View {
        if editorModel.mapMode != .edit {
            content
        } else if isTileEditor {
            // Tile Editor Mode: Simplified toolbar
            content
            #if os(macOS)
                .navigationTitle(String(localized: "Edit Tile", bundle: .module))
            #endif
                .toolbar {
#if !os(macOS)
                    ToolbarItem(placement: titlePlacement) {
                        Text("Edit Tile", bundle: .module)
                            .foregroundStyle(.white)
                    }
#endif
                    ToolbarItem(placement: bottomBarPlacement) {
                        cancelButtonView
                    }
                    ToolbarItem(placement: bottomBarPlacement) {
                        confirmTileButtonView
                    }
                }
#if os(macOS)
                .toolbarBackground(.windowBackground, for: .windowToolbar)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
#endif
        } else {
            // Normal Edit Mode
            content
            .overlay(alignment: .bottom) {
                if !hideScales {
                    GlassEffectContainerView {
                        VStack(spacing: 8) {
                            PinScaleView(model: editorModel)

                            HStack {
                                HexMapScaleView(model: editorModel) { scale in
                                    mapEditController.updateHexScale(scale, editorModel: editorModel)
                                }

                                hexCreationButton
                                    .buttonStyle(.bordered)
                            }

                            MaxSizeScaleView(model: editorModel) { ratio in
                                mapEditController.updateMaxWidth(ratio, editorModel: editorModel)
                            } onMaxHeightChanged: { ratio in
                                mapEditController.updateMaxHeight(ratio, editorModel: editorModel)
                            }
                        }
                        .padding()
                        .frame(maxWidth: 520)
#if !os(visionOS)
                        .glassEffect(.clear)
#endif
                    }
                    .padding(.horizontal)
                    .padding(.bottom, bottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .bouncy, value: hideScales)
            .sheet(isPresented: $showPinSelection) {
                ManagedPresentationView {
                    root.viewController.characterSelection(root: root, selectionModel: selectedPin)
#if !os(macOS)
                        .navigationTransition(.zoom(sourceID: "pin", in: pinSpace))
#endif
                }
            }
            .onChange(of: showPinSelection, initial: false) { _, newValue in
                guard !newValue, !selectedPin.selection.isEmpty else { return }
                let entryId = mapEditController.editController.editorModel.sheetEditorModel.entryId
                let monsters = selectedPin.selection.map { ItemRowModel(itemId: $0.itemId, typeId: .value) }
                withAnimation(reduceMotion ? nil : .default) {
                    mapEditController.addMonsters(entryId: entryId, location: nil, monsters: monsters, number: 1, editorModel: editorModel)
                }
                selectedPin.resetSelection(itemId: nil, entryId: nil)
            }
            .onDisappear() {
                guard !exitReady else { return }
                mapEditController.commitChanges(editorModel: editorModel)
            }
        #if os(macOS)
            .navigationTitle(navTitle)
        #endif
            .toolbar {
                Group {
                    ToolbarItem(placement: .cancellationAction) {
                        previousEntryButton
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        nextEntryButton
                    }
                }
#if os(macOS)
                ToolbarSpacer(.fixed, placement: bottomBarPlacement)
#else
                ToolbarItem(placement: titlePlacement) {
                    Text(verbatim: titlename)
                        .foregroundStyle(.white)
                }

                ToolbarItem(placement: subtitlePlacement) {
                    Text(verbatim: subtitleName)
                        .foregroundStyle(.white)
                }
#endif

                ToolbarItem(placement: bottomBarPlacement) {
                    hideScaleButton
                }

                ToolbarItem(placement: bottomBarPlacement) {
                    refreshSharedMapButton
                }

#if !os(visionOS) && !os(tvOS)
                ToolbarSpacer(.fixed, placement: bottomBarPlacement)
#endif

                ToolbarItemGroup(placement: bottomBarPlacement) {
                    undoButton
                    redoButton

                    toggleDisplayModeButton

                    showPinSelectionButton
                        .matchedTransitionSource(id: "pin", in: pinSpace)
                }

#if !os(visionOS) && !os(tvOS)
                ToolbarSpacer(.flexible, placement: bottomBarPlacement)
#endif

                Group {
                    ToolbarItem(placement: bottomBarPlacement) {
                        cancelButtonView
                    }
                    ToolbarItem(placement: bottomBarPlacement) {
                        closeButtonView
                    }
                }
            }
#if os(macOS)
            .toolbarBackground(.windowBackground, for: .windowToolbar)
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
#endif
        } // end else (edit mode)
    }
}

private extension EditToolBarViewModifier {
    var bottomPadding: CGFloat {
#if os(macOS)
        32
#else
        92
#endif
    }

    var editController: EditController { mapEditController.editController }

    var navTitle: String {
        guard editController.editorModel.sheetEditorModel.entryId != nil else { return titlename }
        return subtitleName
    }

    var titlename: String {
        editorModel.workingCopy?.name ?? String(localized: "Untitled", bundle: .module)
    }

    var subtitleName: String {
        guard let mapModel = editorModel.workingCopy else { return "" }
        let entries = editController.editEntries(for: mapModel)
        guard let entryId = editController.editorModel.sheetEditorModel.entryId else {
            return String(localized: "\(entries.count) Entries", bundle: .module)
        }
        let current = entries.firstIndex(where: { $0.id == entryId })
            .map { "\($0 + 1)/" } ?? ""
        return "\(mapModel[entryId].name) \(current)\(entries.count)"
    }

    @ViewBuilder var nextEntryButton: some View {
        Button {
            resetSelectedIndex(shouldIncrease: true)
        } label: {
            let symbolName = canIncrease ? "forward" : "plus"
            Image(systemName: symbolName)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                .accessibilityLabel(Text("Next Entry", bundle: .module))
        }
        .disabled(isTileEditor)
    }

    @ViewBuilder var previousEntryButton: some View {
        Button {
            resetSelectedIndex(shouldIncrease: false)
        } label: {
            let symbolName = "backward"
            Image(systemName: symbolName)
                .accessibilityLabel(Text("Previous Entry", bundle: .module))
        }
        .disabled(isTileEditor)
    }

    @ViewBuilder var closeButtonView: some View {
        if !editorModel.hideCloseButton {
            Button {
                exitReady = true
                mapEditController.commitChanges(editorModel: editorModel)
#if os(macOS) || os(visionOS)
                scenesManager.dismissWindow(.mapEditor)
#else
                dismiss()
#endif
            } label: {
                let symbolName = "checkmark"
                Image(systemName: symbolName)
                    .accessibilityLabel(Text("Save", bundle: .module))
            }
        }
    }
    
    @ViewBuilder var confirmTileButtonView: some View {
        if !editorModel.hideCloseButton {
            Button {
                exitReady = true
                // Commit changes (tile coordinates are on the working copy's displayConfig)
                mapEditController.commitChanges(editorModel: editorModel)
#if os(macOS) || os(visionOS)
                scenesManager.dismissWindow(isTileEditor ? .mapTileEditor : .mapEditor)
#else
                dismiss()
#endif
            } label: {
                let symbolName = "checkmark"
                Image(systemName: symbolName)
                    .accessibilityLabel(Text("Confirm", bundle: .module))
            }
        }
    }

    @ViewBuilder var cancelButtonView: some View {
        if !editorModel.hideCloseButton {
            Button(role: .destructive) {
                exitReady = true
                mapEditController.discardChanges(editorModel: editorModel)
#if os(macOS) || os(visionOS)
                scenesManager.dismissWindow(isTileEditor ? .mapTileEditor : .mapEditor)
#else
                dismiss()
#endif
            } label: {
                let symbolName = "xmark"
                Image(systemName: symbolName)
                    .accessibilityLabel(Text("Cancel", bundle: .module))
            }
        }
    }

    @ViewBuilder var showPinSelectionButton: some View {
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
                .accessibilityLabel(Text("Choose Map Pins", bundle: .module))
        }
    }

    @ViewBuilder var toggleDisplayModeButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) { editorModel.toggleDisplayMode() }
        } label: {
            Image(systemName: editorModel.iconDisplayMode)
                .contentTransition(.symbolEffect(.replace.byLayer))
                .accessibilityLabel(Text("Display Mode", bundle: .module))
                .accessibilityValue(displayModeAccessibilityValue)
        }
    }

    @ViewBuilder var hideScaleButton: some View {
        if !editorModel.hideCloseButton {
            Button {
                hideScales.toggle()
            } label: {
                let symbolName = (hideScales == true) ? ("square.bottomhalf.filled") : ("square.split.1x2.fill")
                Image(systemName: symbolName)
                    .contentTransition(.symbolEffect(.replace.wholeSymbol))
                    .accessibilityLabel(Text("Toggle Scale Controls", bundle: .module))
            }
        }
    }

    @ViewBuilder var refreshSharedMapButton: some View {
        if isSharedMap {
            Button {
                guard let editedMap = editorModel.workingCopy,
                      networkActions != nil else { return }
                mapEditController.commitChanges(editorModel: editorModel)
                guard root.gameController.refreshSharedMap(from: editedMap) else { return }
                Task {
                    let update = await root.gameController.networkMapContentUpdate(for: editedMap.id)
                    networkActions?.game(update, .generic, nil)
                }
            } label: {
                let symbolName = "arrow.clockwise"
                Image(systemName: symbolName)
                    .accessibilityLabel(Text("Refresh Shared Map", bundle: .module))
            }
        }
    }

    var isSharedMap: Bool {
        guard let mapId = editorModel.workingCopy?.id else { return false }
        return root.gameController.gameModel.itemData[mapId] is MapModel
    }

    @ViewBuilder var hexCreationButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) {
                mapEditController.toggleHexMap(editorModel: editorModel)
                hideScales = false
            }
        } label: {
            let symbolName = editorModel.isHexMap ? "hexagon.fill" : "hexagon"
            Image(systemName: symbolName)
                .contentTransition(.symbolEffect(.replace.wholeSymbol))
                .accessibilityLabel(Text("Hex Grid", bundle: .module))
        }
    }

    @ViewBuilder var undoButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) {
                if !mapEditController.undoPinMutation(editorModel: editorModel) {
                    editController.undo()
                }
            }
        } label: {
            let symbolName = "arrow.uturn.backward"
            Image(systemName: symbolName)
                .accessibilityLabel(Text("Undo", bundle: .module))
        }
        .disabled(!editorModel.pins.canUndoEditorMutation && !editController.canUndo)
    }

    @ViewBuilder var redoButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) {
                if !mapEditController.redoPinMutation(editorModel: editorModel) {
                    editController.redo()
                }
            }
        } label: {
            let symbolName = "arrow.uturn.forward"
            Image(systemName: symbolName)
                .accessibilityLabel(Text("Redo", bundle: .module))
        }
        .disabled(!editorModel.pins.canRedoEditorMutation && !editController.canRedo)
    }

    func resetSelectedIndex(shouldIncrease: Bool) {
        guard let mapModel = editorModel.workingCopy else { return }
        if shouldIncrease && !canIncrease {
            let entryId = editController.addNewEntry(itemId: mapModel.id)
            withAnimation(reduceMotion ? nil : .default) {
                editController.editorModel.sheetEditorModel.entryId = entryId
            }
            return
        }

        let entries = editController.editEntries(for: mapModel)
        guard editController.editorModel.sheetEditorModel.entryId != nil else {
            if let first = entries.first {
                withAnimation(reduceMotion ? nil : .default) {
                    editController.editorModel.sheetEditorModel.entryId = first.id
                }
            }
            return
        }
        guard let index = currentIndex else { return }

        let nextIndex = shouldIncrease ? index.advanced(by: 1) : index.advanced(by: -1)
        if nextIndex >= 0 && nextIndex < entries.count {
            withAnimation(reduceMotion ? nil : .default) {
                editController.editorModel.sheetEditorModel.entryId = entries[nextIndex].id
            }
        }
    }

    var canIncrease: Bool {
        guard let mapModel = editorModel.workingCopy else { return false }
        guard editController.editorModel.sheetEditorModel.entryId != nil else {
            return !editController.editEntries(for: mapModel).isEmpty
        }

        guard let index = currentIndex else { return false }

        return index + 1 < editController.editEntries(for: mapModel).count
    }

    var currentIndex: Int? {
        guard let mapModel = editorModel.workingCopy else { return nil }
        guard let entryId = editController.editorModel.sheetEditorModel.entryId else { return nil }
        return editController.editEntries(for: mapModel).firstIndex(where: { $0.id == entryId })
    }

    var displayModeAccessibilityValue: Text {
        switch editorModel.displayMode {
        case .master:
            Text("Master", bundle: .module)
        case .player:
            Text("Player", bundle: .module)
        case .reader:
            Text("Reader", bundle: .module)
        }
    }

    var bottomBarPlacement: ToolbarItemPlacement {
#if os(macOS)
        .automatic
#else
        .bottomBar
#endif
    }

    var titlePlacement: ToolbarItemPlacement {
#if os(iOS)
        .title
#else
        .automatic
#endif
    }

    var subtitlePlacement: ToolbarItemPlacement {
#if os(iOS)
        .subtitle
#else
        .automatic
#endif
    }
}

#Preview("New Modifier") {
    @Previewable var editController: EditController = .preview
    @Previewable var editorModel = MapEditorSession(
        map: .empty,
        image: AKImage(),
        photoDegrees: 0,
        containerSize: CGSize(width: 400, height: 600)
    )

    NavigationStack {
        VStack {
            Rectangle().fill(Color.green.gradient).ignoresSafeArea()
        }
        .modifier(EditToolBarViewModifier(
            mapEditController: MapEditController(editController: editController),
            editorModel: editorModel,
            isTileEditor: false
        ))
    }
}
