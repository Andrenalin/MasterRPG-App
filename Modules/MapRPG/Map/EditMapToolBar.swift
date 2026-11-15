// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI
import CharacterRPG
import TipKit

struct EditToolBarViewModifier: ViewModifier {
    let mapEditController: MapEditController
    let editorModel: MapEditorSession
    let isTileEditor: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.networkActions) private var networkActions
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(MapRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppWindowSizeModel.self) private var appSizeModel

    @State private var exitReady: Bool = false
    @State private var hideScales: Bool = true
    @State private var showPinSelection: Bool = false

    @State private var selectedPin: ItemSelectionModel = ItemSelectionModel(isSingleSelection: false, allowCollections: true)

    @Namespace private var pinSpace

    private static let autoCommitInterval: Duration = .seconds(30)

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
                            .foregroundStyle(.primary)
                    }
#endif
                    ToolbarItem(placement: bottomBarPlacement) {
                        EditToolBarViewModifierConfirmTileButtonView(
                            mapEditController: mapEditController,
                            editorModel: editorModel,
                            isTileEditor: isTileEditor,
                            exitReady: $exitReady
                        )
                    }
                    ToolbarItemGroup(placement: bottomBarPlacement) {
                        EditToolBarViewModifierUndoButtonView(mapEditController: mapEditController, editorModel: editorModel)
                        EditToolBarViewModifierRedoButtonView(mapEditController: mapEditController, editorModel: editorModel)
                    }
                    ToolbarItem(placement: bottomBarPlacement) {
                        EditToolBarViewModifierCancelButtonView(
                            mapEditController: mapEditController,
                            editorModel: editorModel,
                            isTileEditor: isTileEditor,
                            exitReady: $exitReady
                        )
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
                            if appSizeModel.mode == .compact {
                                HStack(spacing: 24) {
                                    Spacer()
                                    EditToolBarViewModifierUndoButtonView(mapEditController: mapEditController, editorModel: editorModel)
                                        .frame(width: 24, height: 24)
                                    EditToolBarViewModifierRedoButtonView(mapEditController: mapEditController, editorModel: editorModel)
                                        .frame(width: 24, height: 24)
                                    Spacer()
                                }
                                .buttonStyle(.bordered)
                            }

                            PinScaleView(model: editorModel) { isEditing in
                                guard !isEditing else { return }
                                mapEditController.updatePinScale(
                                    editorModel.pinScale,
                                    editorModel: editorModel
                                )
                            }

                            HexMapScaleView(
                                model: editorModel,
                                onToggle: {
                                    mapEditController.toggleHexMap(editorModel: editorModel)
                                    hideScales = false
                                }
                            ) { scale in
                                mapEditController.updateHexScale(scale, editorModel: editorModel)
                            } onScaleEditingChanged: { isEditing in
                                guard !isEditing else { return }
                                mapEditController.commitHexScale(editorModel: editorModel)
                            }

                            if editorModel.maxWidthRatio != 1 || editorModel.maxHeightRatio != 1 || editorModel.isMapSizeOutOfSync {
                                MaxSizeScaleView(model: editorModel) { ratio in
                                    mapEditController.updateMaxWidth(ratio, editorModel: editorModel)
                                } onMaxHeightChanged: { ratio in
                                    mapEditController.updateMaxHeight(ratio, editorModel: editorModel)
                                } onEditingChanged: { isEditing in
                                    guard !isEditing else { return }
                                    mapEditController.commitBoundaryScale(editorModel: editorModel)
                                }
                            }
                        }
                        .padding()
                        .padding(.horizontal, 20)
                        .frame(maxWidth: 520)
#if !os(visionOS)
                        .glassEffect(.regular)
#endif
                    }
                    .padding(.horizontal)
                    .padding(.bottom, bottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .bouncy, value: hideScales)
#if !os(macOS)
            .fullScreenCover(isPresented: $showPinSelection) {
                ManagedPresentationView {
                    root.viewController.characterSelection(root: root, selectionModel: selectedPin)
                        .navigationTransition(.zoom(sourceID: "pin", in: pinSpace))
                }
            }
#endif
            .onChange(of: showPinSelection, initial: false) { _, newValue in
                guard !newValue, !selectedPin.selection.isEmpty else { return }
                let entryId = mapEditController.editController.editorModel.sheetEditorModel.entryId
                let monsters = selectedPin.selection.map { ItemRowModel(itemId: $0.itemId, typeId: .value) }
                withAnimation(reduceMotion ? nil : .default) {
                    mapEditController.addMonsters(entryId: entryId, location: nil, monsters: monsters, number: 1, editorModel: editorModel)
                }
                selectedPin.resetSelection(itemId: nil, entryId: nil)
            }
            // The working copy otherwise commits only on Save or `.onDisappear` — a crash,
            // force-quit or macOS quit with the editor open discarded the whole drawing
            // session, since the app-level exit save only ever saved the un-updated stored
            // model. A periodic auto-commit while this view is on screen gives the same
            // crash resilience without needing every app-exit path to know about an open
            // map editor. See CODE_AUDIT_17 §5.17.
            .task(id: editorModel.workingCopy?.id) {
                guard editorModel.workingCopy != nil else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: EditToolBarViewModifier.autoCommitInterval)
                    guard !Task.isCancelled else { return }
                    mapEditController.commitChanges(editorModel: editorModel)
                }
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
                        EditToolBarViewModifierPreviousEntryButtonView(isTileEditor: isTileEditor) {
                            resetSelectedIndex(shouldIncrease: false)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        EditToolBarViewModifierNextEntryButtonView(isTileEditor: isTileEditor, canIncrease: canIncrease) {
                            resetSelectedIndex(shouldIncrease: true)
                        }
                    }
                }
#if os(macOS)
                ToolbarSpacer(.fixed, placement: bottomBarPlacement)
#else
                Group {
                    ToolbarItem(placement: titlePlacement) {
                        Text(verbatim: titleName)
                            .foregroundStyle(.primary)
                    }
                    
                    ToolbarItem(placement: subtitlePlacement) {
                        Text(verbatim: subtitleName)
                            .foregroundStyle(.secondary)
                    }
                }
#endif

                ToolbarItem(placement: bottomBarPlacement) {
                    EditToolBarViewModifierCloseButtonView(
                        mapEditController: mapEditController,
                        editorModel: editorModel,
                        exitReady: $exitReady
                    )
                }

#if !os(visionOS) && !os(tvOS)
                ToolbarSpacer(.fixed, placement: bottomBarPlacement)
#endif

                Group {
                    ToolbarItem(placement: bottomBarPlacement) {
                        EditToolBarViewModifierHideScaleButtonView(hideCloseButton: editorModel.hideCloseButton, hideScales: $hideScales)
                    }

                    ToolbarItem(placement: bottomBarPlacement) {
                        EditToolBarViewModifierRefreshSharedMapButtonView(
                            mapEditController: mapEditController,
                            editorModel: editorModel,
                            isSharedMap: isSharedMap,
                            sharedMapHasChanges: sharedMapHasChanges
                        )
                    }
                }
#if !os(visionOS) && !os(tvOS)
                ToolbarSpacer(.fixed, placement: bottomBarPlacement)
#endif

                ToolbarItemGroup(placement: bottomBarPlacement) {
                    if appSizeModel.mode != .compact {
                        EditToolBarViewModifierUndoButtonView(mapEditController: mapEditController, editorModel: editorModel)
                        EditToolBarViewModifierRedoButtonView(mapEditController: mapEditController, editorModel: editorModel)
                    }

#if os(iOS)
                    if editorModel.canDrawWithPencil {
                        EditToolBarViewModifierPencilDrawButtonView(editorModel: editorModel)
                    }
#endif

                    EditToolBarViewModifierToggleDisplayModeButtonView(
                        editorModel: editorModel,
                        displayModeAccessibilityValue: displayModeAccessibilityValue
                    )

                    EditToolBarViewModifierShowPinSelectionButtonView(showPinSelection: $showPinSelection)
                        .matchedTransitionSource(id: "pin", in: pinSpace)
                }

#if !os(visionOS) && !os(tvOS)
                ToolbarSpacer(.flexible, placement: bottomBarPlacement)
#endif

                ToolbarItem(placement: bottomBarPlacement) {
                    EditToolBarViewModifierCancelButtonView(
                        mapEditController: mapEditController,
                        editorModel: editorModel,
                        isTileEditor: isTileEditor,
                        exitReady: $exitReady
                    )
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
        guard editController.editorModel.sheetEditorModel.entryId != nil else { return titleName }
        return subtitleName
    }

    var titleName: String {
        editorModel.workingCopy?.name ?? String(localized: "Untitled", bundle: .module)
    }

    var subtitleName: String {
        guard let mapModel = editorModel.workingCopy else { return "" }
        // Counted in place: the title is read on every toolbar evaluation, and a filtered
        // array of the entries was built each time. See CODE_AUDIT_26 §7.54.
        let entryCount = mapModel.entries.count { !$0.isHexGrid }
        guard let entryId = editController.editorModel.sheetEditorModel.entryId else {
            return String(localized: "\(entryCount) Entries", bundle: .module)
        }
        var position: Int?
        var seen = 0
        for entry in mapModel.entries where !entry.isHexGrid {
            seen += 1
            if entry.id == entryId { position = seen; break }
        }
        let current = position.map { "\($0)/" } ?? ""
        return "\(mapModel[entryId].name) \(current)\(entryCount)"
    }

    var isSharedMap: Bool {
        guard let mapId = editorModel.workingCopy?.id else { return false }
        return root.gameController.gameModel.itemData[mapId] is MapModel
    }

    var sharedMapHasChanges: Bool {
        guard let editedMap = editorModel.workingCopy else { return false }
        let savedMap = root.itemController.itemOrEmpty(for: editedMap.id)
        return !editedMap.isSame(savedMap)
            || editorModel.pinScale != savedMap.pinScale
            || editorModel.hexScale != savedMap.hexMapScale
    }

    func resetSelectedIndex(shouldIncrease: Bool) {
        guard let mapModel = editorModel.workingCopy else { return }
        if shouldIncrease && !canIncrease {
            guard let entryId = mapEditController.addEntry(editorModel: editorModel) else {
                return
            }
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

// Extracted button subviews for this toolbar's overflow items live in
// EditMapToolBarButtons.swift — see CODE_AUDIT §9.13.

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
