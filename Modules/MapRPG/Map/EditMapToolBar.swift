// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI
import CharacterRPG

struct EditToolBarViewModifier: ViewModifier {
    let mapEditController: MapEditController
    let editorModel: MapEditorModel
    let isTileEditor: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(MapRootModel.self) private var root

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
        } else {
            // Normal Edit Mode
            content
            .overlay(alignment: .bottom) {
                GlassEffectContainerView {
                    VStack(spacing: 8) {
                        PinScaleView(model: editorModel)

                        HexMapScaleView(model: editorModel) { scale in
                            mapEditController.updateHexScale(scale, editorModel: editorModel)
                        }
                    }
                    .padding()
                    #if !os(visionOS)
                    .glassEffect(.clear)
                    #endif
                    .offset(x: hideScales ? -2500 : 0)
                    .opacity(hideScales ? 0 : 1)
                    .animation(.bouncy, value: hideScales)
                }
                .padding(.horizontal)
                .padding(.bottom, bottomPadding)
            }
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
                let entryId = mapEditController.editController.sheetEditorModel.entryId
                let monsters = selectedPin.selection.map { ItemRowModel(itemId: $0.itemId, typeId: .value) }
                withAnimation {
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
                ToolbarItem(placement: .cancellationAction) {
                    previousEntryButton
                }
                ToolbarItem(placement: .confirmationAction) {
                    nextEntryButton
                }

#if os(macOS)
                ToolbarSpacer(.fixed, placement: bottomBarPlacement)
#else
                ToolbarItem(placement: titlePlacement) {
                    Text(titlename)
                        .foregroundStyle(.white)
                }

                ToolbarItem(placement: subtitlePlacement) {
                    Text(subtitleName)
                        .foregroundStyle(.white)
                }
#endif

                ToolbarItem(placement: bottomBarPlacement) {
                    hideScaleButton
                }

#if !os(visionOS) && !os(tvOS)
                ToolbarSpacer(.fixed, placement: bottomBarPlacement)
#endif

                ToolbarItemGroup(placement: bottomBarPlacement) {
                    undoButton
                    redoButton

                    toggleDisplayModeButton
                    hexCreationButton

                    showPinSelectionButton
                        .matchedTransitionSource(id: "pin", in: pinSpace)
                }

#if !os(visionOS) && !os(tvOS)
                ToolbarSpacer(.flexible, placement: bottomBarPlacement)
#endif

                ToolbarItem(placement: bottomBarPlacement) {
                    cancelButtonView
                }
                ToolbarItem(placement: bottomBarPlacement) {
                    closeButtonView
                }
            }
        } // end else (edit mode)
    }
}

private extension EditToolBarViewModifier {
    var bottomPadding: CGFloat {
#if os(macOS)
        16
#else
        80
#endif
    }

    var editController: EditController { mapEditController.editController }

    var navTitle: String {
        guard editController.sheetEditorModel.entryId != nil else { return titlename }
        return subtitleName
    }

    var titlename: String {
        editorModel.workingCopy?.name ?? "Untitled"
    }

    var subtitleName: String {
        guard let mapModel = editorModel.workingCopy else { return "" }
        let entries = editController.editEntries(for: mapModel)
        guard let entryId = editController.sheetEditorModel.entryId else {
            return "\(entries.count) Entries"
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
                .accessibilityLabel(AccessibilityLabelCache.shared.label(for: symbolName) ?? "Next")
        }
        .disabled(isTileEditor)
    }

    @ViewBuilder var previousEntryButton: some View {
        Button {
            resetSelectedIndex(shouldIncrease: false)
        } label: {
            let symbolName = "backward"
            Image(systemName: symbolName)
                .accessibilityLabel(AccessibilityLabelCache.shared.label(for: symbolName) ?? "Previous")
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
                    .accessibilityLabel(AccessibilityLabelCache.shared.label(for: symbolName) ?? "Save")
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
                scenesManager.dismissWindow(.mapEditor)
#else
                dismiss()
#endif
            } label: {
                let symbolName = "checkmark"
                Image(systemName: symbolName)
                    .accessibilityLabel(AccessibilityLabelCache.shared.label(for: symbolName) ?? "Confirm")
            }
        }
    }

    @ViewBuilder var cancelButtonView: some View {
        if !editorModel.hideCloseButton {
            Button(role: .destructive) {
                exitReady = true
                mapEditController.discardChanges(editorModel: editorModel)
#if os(macOS) || os(visionOS)
                scenesManager.dismissWindow(.mapEditor)
#else
                dismiss()
#endif
            } label: {
                let symbolName = "xmark"
                Image(systemName: symbolName)
                    .accessibilityLabel(AccessibilityLabelCache.shared.label(for: symbolName) ?? "Cancel")
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
                .accessibilityLabel(AccessibilityLabelCache.shared.label(for: symbolName) ?? "Pin selection")
        }
    }

    @ViewBuilder var toggleDisplayModeButton: some View {
        Button {
            withAnimation { editorModel.toggleDisplayMode() }
        } label: {
            Image(systemName: editorModel.iconDisplayMode)
                .contentTransition(.symbolEffect(.replace.byLayer))
                .accessibilityLabel(AccessibilityLabelCache.shared.label(for: editorModel.iconDisplayMode) ?? "Display mode")
                .accessibilityValue(editorModel.displayMode == .master ? "Master" :
                                   editorModel.displayMode == .player ? "Player" : "Reader")
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
                    .accessibilityLabel(AccessibilityLabelCache.shared.label(for: symbolName) ?? "Toggle scales")
            }
        }
    }

    @ViewBuilder var hexCreationButton: some View {
        Button {
            withAnimation {
                mapEditController.toggleHexMap(editorModel: editorModel)
                hideScales = false
            }
        } label: {
            let symbolName = editorModel.isHexMap ? "hexagon.fill" : "hexagon"
            Image(systemName: symbolName)
                .contentTransition(.symbolEffect(.replace.wholeSymbol))
                .accessibilityLabel(AccessibilityLabelCache.shared.label(for: symbolName) ?? "Hex map")
        }
    }

    @ViewBuilder var undoButton: some View {
        Button {
            withAnimation { editController.undo() }
        } label: {
            let symbolName = "arrow.uturn.backward"
            Image(systemName: symbolName)
                .accessibilityLabel(AccessibilityLabelCache.shared.label(for: symbolName) ?? "Undo")
        }
        .disabled(!editController.canUndo)
    }

    @ViewBuilder var redoButton: some View {
        Button {
            withAnimation { editController.redo() }
        } label: {
            let symbolName = "arrow.uturn.forward"
            Image(systemName: symbolName)
                .accessibilityLabel(AccessibilityLabelCache.shared.label(for: symbolName) ?? "Redo")
        }
        .disabled(!editController.canRedo)
    }

    func resetSelectedIndex(shouldIncrease: Bool) {
        guard let mapModel = editorModel.workingCopy else { return }
        if shouldIncrease && !canIncrease {
            let entryId = editController.addNewEntry(itemId: mapModel.id)
            withAnimation { editController.sheetEditorModel.entryId = entryId }
            return
        }

        let entries = editController.editEntries(for: mapModel)
        guard editController.sheetEditorModel.entryId != nil else {
            if let first = entries.first {
                withAnimation { editController.sheetEditorModel.entryId = first.id }
            }
            return
        }
        guard let index = currentIndex else { return }

        let nextIndex = shouldIncrease ? index.advanced(by: 1) : index.advanced(by: -1)
        if nextIndex >= 0 && nextIndex < entries.count {
            withAnimation { editController.sheetEditorModel.entryId = entries[nextIndex].id }
        }
    }

    var canIncrease: Bool {
        guard let mapModel = editorModel.workingCopy else { return false }
        guard editController.sheetEditorModel.entryId != nil else {
            return !editController.editEntries(for: mapModel).isEmpty
        }

        guard let index = currentIndex else { return false }

        return index + 1 < editController.editEntries(for: mapModel).count
    }

    var currentIndex: Int? {
        guard let mapModel = editorModel.workingCopy else { return nil }
        guard let entryId = editController.sheetEditorModel.entryId else { return nil }
        return editController.editEntries(for: mapModel).firstIndex(where: { $0.id == entryId })
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

private struct PinScaleView: View {
    @Bindable var model: MapEditorModel

    var body: some View {
        HStack {
#if !os(tvOS)
            Text("Pin Scale", bundle: .module)
                .foregroundStyle(.white)
            Slider(value: $model.pinScale, in: 0.5 ... 3.5) {
                Text("Pin Scale", bundle: .module)
            }
            .accessibilityValue(String(format: "%.1f×", model.pinScale))
            .labelsHidden()
#endif
        }
        .opacity(model.hideCloseButton ? 0 : 1)
    }
}

private struct HexMapScaleView: View {
    @Bindable var model: MapEditorModel
    let onScaleChanged: (Double) -> Void

    var body: some View {
        HStack {
#if !os(tvOS)
            Text("Hex Scale", bundle: .module)
                .foregroundStyle(.white)
            Slider(value: $model.hexScale, in: 20 ... 200) {
                Text("Hex Scale", bundle: .module)
            }
            .onChange(of: model.hexScale) {
                onScaleChanged(model.hexScale)
            }
            .accessibilityValue(String(format: "%.0f", model.hexScale))
            .labelsHidden()
#endif
        }
        .opacity(model.hideCloseButton ? 0 : 1)
    }
}

#Preview("New Modifier") {
    @Previewable var editController: EditController = .preview
    @Previewable var editorModel = MapEditorModel(
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
