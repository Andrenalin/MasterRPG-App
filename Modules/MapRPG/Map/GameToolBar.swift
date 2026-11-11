// @copyright André Trettin

import CoreRPG
import SwiftUI
import CharacterRPG

/// Shared by the 2D map canvas (`MapEditorSession`) and GameRPG's 3D table
/// (`GameTableModel`, via `GameToolBarSession`) — the exact same toolbar,
/// buttons, and button actions render for both, so the game master sees one
/// consistent set of controls regardless of which representation is on screen.
struct GameToolBar<Session: GameToolBarSession>: View {
    /// Grows with Dynamic Type instead of a fixed 24 pt. See CODE_AUDIT_18 §8.3.
    @ScaledMetric private var iconSize: CGFloat = 24
    let editController: EditController
    let model: Session
    let isMaster: Bool

    @Environment(MapRootModel.self) private var root
    @Environment(\.dismiss) private var dismiss
    @Environment(\.networkActions) private var networkActions
    @Environment(AppWindowSizeModel.self) private var appWindowSizeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showToolBar: Bool = true
    @State private var hideScales: Bool = true

    var body: some View {
        GlassEffectContainerAll {
            VStack(alignment: .leading, spacing: 8) {
            if appWindowSizeModel.mode == .compact {
                VStack(spacing: 8) {
                    GameToolBarPinScaleView(model: model)
                        .padding(.horizontal)

                    HStack(spacing: 8) {
                        GameToolBarReshareButtonView(model: model)
                        GameToolBarHexMapScaleView(model: model)
                    }
                    .padding([.horizontal, .bottom])
                }
                .offset(x: hideScales || !showToolBar ? -500 : 0)
                .allowsHitTesting(!hideScales && showToolBar)
                .accessibilityHidden(hideScales || !showToolBar)
                .animation(reduceMotion ? nil : .bouncy, value: hideScales)
            } else {
#if os(macOS)
                Divider()
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
#endif
            }

        HStack {
            if isMaster {
                Button {
                    withAnimation(reduceMotion ? nil : .default) { showToolBar.toggle() }
                } label: {
                    Image(systemName: showToolBar ? "arrow.left.square.fill" : "arrow.right.square")
                        .contentTransition(.symbolEffect(.replace.downUp))
                        .frame(height: iconSize)
                }
                .selectedRoundButton(
                    title: String(localized: toggleToolBarTitle),
                    module: .map,
                    isSelected: showToolBar
                )
            }
            HStack {
                if showToolBar {
                    HStack {
                        if isMaster {
#if os(macOS) || os(visionOS)
                            GameToolBarBattleRoundButtonView()
#endif
                            Button {
                                withAnimation(reduceMotion ? nil : .default) {
                                    model.displayMode = model.displayMode.toggled()
                                }
                            } label: {
                                Image(systemName: model.displayMode.toolBarIcon)
                                    .contentTransition(.symbolEffect(.replace.byLayer))
                                    .frame(width: iconSize * 28 / 24, height: iconSize)
                                    .accessibilityValue(displayModeAccessibilityValue)
                            }
                            .selectedRoundButton(
                                title: String(localized: "Display Mode", bundle: .module),
                                module: .map,
                                isSelected: model.displayMode != .master
                            )

                            GameToolBarBarButtonsView(model: model)

                            if appWindowSizeModel.mode == .regular {
                                GameToolBarHideScaleButtonView(hideScales: $hideScales)

                                if !hideScales {
                                    HStack(spacing: 8) {
                                        GameToolBarReshareButtonView(model: model)
                                        GameToolBarHexMapScaleView(model: model)
                                    }
                                    GameToolBarPinScaleView(model: model)
                                }
                            }
                            Spacer()
                            if appWindowSizeModel.mode == .compact {
                                GameToolBarHideScaleButtonView(hideScales: $hideScales)
                            }
                        }
                    }
                }
            }
            .applyIf(!showToolBar) {
                $0.frame(width: 0)
            }
            .offset(x: showToolBar ? 0 : -250)
        }
        }
        .padding(.horizontal)
        .animation(
            reduceMotion ? nil : .bouncy.delay(hideScales ? 0 : 0.25),
            value: showToolBar
        )
        }
    }

    private var toggleToolBarTitle: LocalizedStringResource {
        showToolBar
            ? LocalizedStringResource("Hide Toolbar", bundle: .module)
            : LocalizedStringResource("Show Toolbar", bundle: .module)
    }

    private var displayModeAccessibilityValue: Text {
        switch model.displayMode {
        case .master:
            Text("Master", bundle: .module)
        case .player:
            Text("Player", bundle: .module)
        case .reader:
            Text("Reader", bundle: .module)
        }
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)
//
// Each gives SwiftUI its own diffing boundary, instead of the previous computed
// `some View` properties on `GameToolBar` itself that all re-evaluated whenever any part
// of `GameToolBar`'s body did.

private struct GameToolBarBarButtonsView<Session: GameToolBarSession>: View {
    /// Grows with Dynamic Type instead of a fixed 24 pt. See CODE_AUDIT_18 §8.3.
    @ScaledMetric private var iconSize: CGFloat = 24
    let model: Session

    @Environment(MapRootModel.self) private var root
    @Environment(\.networkActions) private var networkActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) {
                model.isStreaming.toggle()
            }
            if model.isStreaming {
                model.sendMapUpdates()
            }
        } label: {
            let symbolName = "person.2\(model.isStreaming ? ".fill" : ".slash")"
            Image(systemName: symbolName)
                .contentTransition(.symbolEffect(.replace.wholeSymbol))
                .frame(height: iconSize)
                .accessibilityValue(
                    model.isStreaming
                        ? Text("Enabled", bundle: .module)
                        : Text("Disabled", bundle: .module)
                )
        }
        .selectedRoundButton(
            title: String(localized: "Share Map", bundle: .module),
            module: .map,
            isSelected: model.isStreaming
        )

        ChooseMapPinsButton(root: root, focusedRoomId: model.focusedRoomId) {
            if model.isStreaming { model.sendMapUpdates() }
        }

        Button {
            togglePointingMode()
        } label: {
            let symbolName = "hand.point.up.left\(model.isPointing ? ".fill" : "")"
            Image(systemName: symbolName)
                .contentTransition(.symbolEffect(.replace.offUp))
                .frame(height: iconSize)
                .accessibilityValue(
                    model.isPointing
                        ? Text("Enabled", bundle: .module)
                        : Text("Disabled", bundle: .module)
                )
        }
        .selectedRoundButton(
            title: String(localized: "Pointing Mode", bundle: .module),
            module: .map,
            isSelected: model.isPointing
        )

        Button {
            // Like every other edit, it reaches the players only while sharing is on; the game
            // master's own screen is always cleared.
            networkActions?.clearMap(model.isStreaming)
        } label: {
            Image(systemName: "xmark.rectangle")
                .frame(height: iconSize)
        }
        .selectedRoundButton(
            title: String(localized: "Clear Map", bundle: .module),
            module: .map,
            isSelected: false
        )
    }

    /// Turning the shared pointer on reveals and centers it — folding in what
    /// used to be the 3D table's separate "Center Pointer" button; turning it
    /// off hides it. One action for both renderers: it only mutates the map's
    /// pointer pin through `root`, nothing view-specific.
    private func togglePointingMode() {
        guard let mapId = model.currentMapId else { return }
        withAnimation(reduceMotion ? nil : .default) {
            if model.isPointing {
                guard root.gameController.togglePointer(itemId: mapId) else { return }
            } else {
                guard root.gameController.showPointerAtMapCenter(itemId: mapId) else { return }
            }
            model.isPointing.toggle()
        }
        if model.isStreaming { model.sendMapUpdates() }
    }
}

private struct GameToolBarPinScaleView<Session: GameToolBarSession>: View {
    let model: Session

    @ViewBuilder
    var body: some View {
        @Bindable var model = model
        HStack {
#if !os(tvOS)
            Text("Pin Scale", bundle: .module)

            Slider(value: $model.pinScale, in: 0.5 ... 3.5) {
                Text("Pin Scale", bundle: .module)
            }
            .labelsHidden()
            .accessibilityValue(
                Double(model.pinScale).formatted(
                    FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
                )
            )
#endif
        }
    }
}

private struct GameToolBarHexMapScaleView<Session: GameToolBarSession>: View {
    /// Grows with Dynamic Type instead of a fixed 24 pt. See CODE_AUDIT_18 §8.3.
    @ScaledMetric private var iconSize: CGFloat = 24
    let model: Session
    /// True while the scale slider is dragged: the grid is rebuilt when the drag ends.
    @State private var isEditingHexScale = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    var body: some View {
        @Bindable var model = model
        HStack {
#if !os(tvOS)
            Button {
                withAnimation(reduceMotion ? nil : .default) {
                    model.toggleHexMap()
                }
            } label: {
                let symbolName = model.isHexMap ? "hexagon.fill" : "hexagon"
                Image(systemName: symbolName)
                    .contentTransition(.symbolEffect(.replace.wholeSymbol))
                    .frame(width: iconSize, height: iconSize)
                    .accessibilityLabel(Text("Hex Grid", bundle: .module))
                    .accessibilityValue(
                        model.isHexMap
                            ? Text("Enabled", bundle: .module)
                            : Text("Disabled", bundle: .module)
                    )
            }
            .frame(minWidth: 44, minHeight: 44)
            .gameOverlayControlStyle(isSelected: model.isHexMap)

            Text("Hex Scale", bundle: .module)
                .foregroundStyle(.primary)

            Slider(value: $model.hexScale, in: 20 ... 200) {
                Text("Hex Scale", bundle: .module)
            } onEditingChanged: { isEditing in
                isEditingHexScale = isEditing
                if !isEditing {
                    model.commitHexScale()
                }
            }
            // A change outside a drag (VoiceOver's adjust action, a key press) has no release.
            .onChange(of: model.hexScale) {
                if !isEditingHexScale {
                    model.commitHexScale()
                }
            }
            .labelsHidden()
            .accessibilityValue(model.hexScale.formatted(.number.precision(.fractionLength(0))))
#endif
        }
    }
}

#if os(macOS) || os(visionOS)
/// Opens / closes the Battle Round window (iOS keeps it in the game menu).
private struct GameToolBarBattleRoundButtonView: View {
    @ScaledMetric private var iconSize: CGFloat = 24
    @Environment(ScenesManager.self) private var scenesManager

    var body: some View {
        let isPresented = scenesManager.getSceneState(for: .battleRound).isPresentedInGameMenu
        Button {
            if isPresented {
                scenesManager.dismissWindow(.battleRound)
            } else {
                scenesManager.openWindow(.battleRound)
            }
        } label: {
            Image(systemName: "shield.lefthalf.filled")
                .frame(width: iconSize, height: iconSize)
        }
        .selectedRoundButton(
            title: String(localized: "Battle Round", bundle: .module),
            module: .map,
            isSelected: isPresented
        )
    }
}
#endif

private struct GameToolBarHideScaleButtonView: View {
    /// Grows with Dynamic Type instead of a fixed 24 pt. See CODE_AUDIT_18 §8.3.
    @ScaledMetric private var iconSize: CGFloat = 24
    @Binding var hideScales: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) { hideScales.toggle() }
        } label: {
            let symbolName = "square.arrowtriangle.4.outward"
            Image(systemName: symbolName)
                .frame(width: iconSize, height: iconSize)
        }
        .selectedRoundButton(
            title: String(localized: "Toggle Scale Controls", bundle: .module),
            module: .map,
            isSelected: !hideScales
        )
    }
}

private struct GameToolBarReshareButtonView<Session: GameToolBarSession>: View {
    /// Grows with Dynamic Type instead of a fixed 24 pt. See CODE_AUDIT_18 §8.3.
    @ScaledMetric private var iconSize: CGFloat = 24
    let model: Session

    @Environment(MapRootModel.self) private var root
    @Environment(\.networkActions) private var networkActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    var body: some View {
        Button {
            guard let mapId = model.currentMapId else { return }
            let root = root
            let networkActions = networkActions
            root.rootModel.enqueueMapContentSend {
                let update = await root.gameController.networkMapContentUpdate(for: mapId)
                networkActions?.game(update, .generic, nil)
            }
            withAnimation(reduceMotion ? nil : .default) {
                model.resetReshare()
            }
        } label: {
            let symbolName = "square.and.arrow.up"
            Image(systemName: symbolName)
                .frame(width: iconSize, height: iconSize)
        }
        .disabled(!model.canReshare)
        .opacity(model.canReshare ? 1 : 0)
        .allowsHitTesting(model.canReshare)
        .accessibilityHidden(!model.canReshare)
        .selectedRoundButton(
            title: String(localized: "Refresh Shared Map", bundle: .module),
            module: .map,
            isSelected: false
        )
    }
}

#Preview {
    @Previewable var editController: EditController = .preview
    @Previewable var editorModel = MapEditorSession(
        map: .empty,
        image: AKImage(),
        photoDegrees: 0,
        containerSize: CGSize(width: 400, height: 600),
        mapMode: .gameMaster
    )
    HStack {
        GameToolBar(editController: editController, model: editorModel, isMaster: true)
            .environment(MapRootModel.preview)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
