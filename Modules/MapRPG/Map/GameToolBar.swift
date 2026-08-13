// @copyright André Trettin

import CoreRPG
import SwiftUI
import CharacterRPG

/// Shared by the 2D map canvas (`MapEditorSession`) and GameRPG's 3D table
/// (`GameTableModel`, via `GameToolBarSession`) — the exact same toolbar,
/// buttons, and button actions render for both, so the game master sees one
/// consistent set of controls regardless of which representation is on screen.
struct GameToolBar<Session: GameToolBarSession>: View {
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
                    pinScaleView
                        .padding(.horizontal)

                    HStack(spacing: 8) {
                        reshareButtonView
                        hexMapScaleView
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
                        .frame(height: 24)
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
                            Button {
                                withAnimation(reduceMotion ? nil : .default) {
                                    model.displayMode = model.displayMode.toggled()
                                }
                            } label: {
                                Image(systemName: model.displayMode.toolBarIcon)
                                    .contentTransition(.symbolEffect(.replace.byLayer))
                                    .frame(width: 28, height: 24)
                                    .accessibilityValue(displayModeAccessibilityValue)
                            }
                            .selectedRoundButton(
                                title: String(localized: "Display Mode", bundle: .module),
                                module: .map,
                                isSelected: model.displayMode != .master
                            )

                            barButtonViews

                            if appWindowSizeModel.mode == .regular {
                                hideScaleButtonView

                                if !hideScales {
                                    HStack(spacing: 8) {
                                        reshareButtonView
                                        hexMapScaleView
                                    }
                                    pinScaleView
                                }
                            }
                            Spacer()
                            if appWindowSizeModel.mode == .compact {
                                hideScaleButtonView
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

    @ViewBuilder
    var barButtonViews: some View {
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
                .frame(height: 24)
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
                .frame(height: 24)
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
                let mapModel = root.gameController.currentItem()
                let center = CGPoint(x: mapModel.width / 2, y: mapModel.height / 2)
                let moved = root.gameController.movePointer(itemId: mapId, location: center)
                let revealed = mapModel.pointer.isShown
                    ? false
                    : root.gameController.togglePointer(itemId: mapId)
                guard moved || revealed else { return }
            }
            model.isPointing.toggle()
        }
        if model.isStreaming { model.sendMapUpdates() }
    }

    @ViewBuilder
    var pinScaleView: some View {
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

    @ViewBuilder
    var hexMapScaleView: some View {
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
                    .frame(width: 24, height: 24)
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
            }
            .labelsHidden()
            .accessibilityValue(model.hexScale.formatted(.number.precision(.fractionLength(0))))
#endif
        }
    }

    @ViewBuilder
    var hideScaleButtonView: some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) { hideScales.toggle() }
        } label: {
            let symbolName = "square.arrowtriangle.4.outward"
            Image(systemName: symbolName)
                .frame(width: 24, height: 24)
        }
        .selectedRoundButton(
            title: String(localized: "Toggle Scale Controls", bundle: .module),
            module: .map,
            isSelected: !hideScales
        )
    }

    @ViewBuilder
    var reshareButtonView: some View {
        Button {
            guard let mapId = model.currentMapId else { return }
            Task {
                let update = await root.gameController.networkMapContentUpdate(for: mapId)
                networkActions?.game(update, .generic, nil)
            }
            withAnimation(reduceMotion ? nil : .default) {
                model.resetReshare()
            }
        } label: {
            let symbolName = "square.and.arrow.up"
            Image(systemName: symbolName)
                .frame(width: 24, height: 24)
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
