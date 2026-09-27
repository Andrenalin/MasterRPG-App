// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI
import CharacterRPG
import TipKit

// MARK: - Extracted subviews (CODE_AUDIT §8.3)
//
// Each gives SwiftUI its own diffing boundary, instead of the previous computed
// `some View` properties on `EditToolBarViewModifier` itself that all re-evaluated whenever
// any part of the modifier's body did. Split out of EditMapToolBar.swift — see CODE_AUDIT §9.13.

struct EditToolBarViewModifierNextEntryButtonView: View {
    let isTileEditor: Bool
    let canIncrease: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            let symbolName = canIncrease ? "forward" : "plus"
            Image(systemName: symbolName)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                .accessibilityLabel(Text("Next Entry", bundle: .module))
        }
        .disabled(isTileEditor)
    }
}

struct EditToolBarViewModifierPreviousEntryButtonView: View {
    let isTileEditor: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            let symbolName = "backward"
            Image(systemName: symbolName)
                .accessibilityLabel(Text("Previous Entry", bundle: .module))
        }
        .disabled(isTileEditor)
    }
}

struct EditToolBarViewModifierCloseButtonView: View {
    let mapEditController: MapEditController
    let editorModel: MapEditorSession
    @Binding var exitReady: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(ScenesManager.self) private var scenesManager

    @ViewBuilder
    var body: some View {
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
}

struct EditToolBarViewModifierConfirmTileButtonView: View {
    let mapEditController: MapEditController
    let editorModel: MapEditorSession
    let isTileEditor: Bool
    @Binding var exitReady: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(ScenesManager.self) private var scenesManager

    @ViewBuilder
    var body: some View {
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
}

struct EditToolBarViewModifierCancelButtonView: View {
    let mapEditController: MapEditController
    let editorModel: MapEditorSession
    let isTileEditor: Bool
    @Binding var exitReady: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(ScenesManager.self) private var scenesManager

    @ViewBuilder
    var body: some View {
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
}

struct EditToolBarViewModifierShowPinSelectionButtonView: View {
    @Binding var showPinSelection: Bool

    @Environment(ScenesManager.self) private var scenesManager

    var body: some View {
        Button {
#if os(macOS)
            scenesManager.openWindow(SceneId(rawValue: NetworkModules.value.linkWindowId))
#else
            showPinSelection.toggle()
#endif
            MasterRPGTips.recordMapToolUsed()
        } label: {
            let symbolName = "mappin\(showPinSelection ? ".and.ellipse" : "")"
            Image(systemName: symbolName)
                .contentTransition(.symbolEffect(.replace.wholeSymbol))
                .accessibilityLabel(Text("Choose Map Pins", bundle: .module))
        }
        .popoverTip(MasterRPGTips.useMapTools)
    }
}

struct EditToolBarViewModifierToggleDisplayModeButtonView: View {
    let editorModel: MapEditorSession
    let displayModeAccessibilityValue: Text

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) { editorModel.toggleDisplayMode() }
            MasterRPGTips.recordMapToolUsed()
        } label: {
            Image(systemName: editorModel.iconDisplayMode)
                .contentTransition(.symbolEffect(.replace.byLayer))
                .accessibilityLabel(Text("Display Mode", bundle: .module))
                .accessibilityValue(displayModeAccessibilityValue)
        }
    }
}

struct EditToolBarViewModifierHideScaleButtonView: View {
    let hideCloseButton: Bool
    @Binding var hideScales: Bool

    @ViewBuilder
    var body: some View {
        if !hideCloseButton {
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
}

struct EditToolBarViewModifierRefreshSharedMapButtonView: View {
    let mapEditController: MapEditController
    let editorModel: MapEditorSession
    let isSharedMap: Bool
    let sharedMapHasChanges: Bool

    @Environment(MapRootModel.self) private var root
    @Environment(\.networkActions) private var networkActions

    @ViewBuilder
    var body: some View {
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
            .disabled(!sharedMapHasChanges)
            .opacity(sharedMapHasChanges ? 1 : 0)
            .allowsHitTesting(sharedMapHasChanges)
            .accessibilityHidden(!sharedMapHasChanges)
        }
    }
}

/// Repairs a map whose persisted size disagrees with its photo's own pixel size — see
/// `MapEditController.fixMapSizeToPhoto(editorModel:)`. Hidden otherwise, since this is a
/// one-shot repair, not something a correctly-sized map ever needs.
struct EditToolBarViewModifierFixMapSizeButtonView: View {
    let mapEditController: MapEditController
    let editorModel: MapEditorSession
    let isOutOfSync: Bool

    @ViewBuilder
    var body: some View {
        if isOutOfSync {
            Button {
                mapEditController.fixMapSizeToPhoto(editorModel: editorModel)
            } label: {
                Image(systemName: "aspectratio")
                    .accessibilityLabel(Text("Fix Map Size to Photo", bundle: .module))
            }
        }
    }
}

struct EditToolBarViewModifierUndoButtonView: View {
    let mapEditController: MapEditController
    let editorModel: MapEditorSession

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) {
                _ = mapEditController.undo(editorModel: editorModel)
            }
        } label: {
            let symbolName = "arrow.uturn.backward"
            Image(systemName: symbolName)
                .accessibilityLabel(Text("Undo", bundle: .module))
        }
        .disabled(!editorModel.history.canUndo)
    }
}

struct EditToolBarViewModifierRedoButtonView: View {
    let mapEditController: MapEditController
    let editorModel: MapEditorSession

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) {
                _ = mapEditController.redo(editorModel: editorModel)
            }
        } label: {
            let symbolName = "arrow.uturn.forward"
            Image(systemName: symbolName)
                .accessibilityLabel(Text("Redo", bundle: .module))
        }
        .disabled(!editorModel.history.canRedo)
    }
}
