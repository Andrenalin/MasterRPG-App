// @copyright André Trettin

import CoreRPG
import SwiftUI
import CharacterRPG

struct GameToolBar: View {
    let editController: EditController
    let model: MapEditorModel
    let isMaster: Bool

    @Environment(MapRootModel.self) private var root
    @Environment(\.dismiss) private var dismiss
    @Environment(\.networkActions) private var networkActions
    @Environment(AppWindowSizeModel.self) private var appWindowSizeModel

    @Environment(ScenesManager.self) private var scenesManager

    @State private var showPinSelection: Bool = false
    @State private var selectedPin: ItemSelectionModel = ItemSelectionModel(isSingleSelection: false, allowCollections: true)

    @State private var showToolBar: Bool = true
    @State private var hideScales: Bool = true

    @Namespace private var pinSpace

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if appWindowSizeModel.mode == .compact {
                VStack(spacing: 8) {
                    pinScaleView
                        .padding(.horizontal)

                    hexMapScaleView
                        .padding([.horizontal, .bottom])
                }
                .offset(x: hideScales || !showToolBar ? -500 : 0)
                .animation(.bouncy, value: hideScales)
            } else {
#if os(macOS)
                Divider()
                    .opacity(0)
#endif
            }

        HStack {
            if isMaster {
                Button {
                    withAnimation { showToolBar.toggle() }
                } label: {
                    Image(systemName: showToolBar ? "arrow.left.square.fill" : "arrow.right.square")
                        .contentTransition(.symbolEffect(.replace.downUp))
                        .frame(height: 24)
                        .accessibilityLabel(AccessibilityLabelCache.shared.label(for: showToolBar ? "arrow.left.square.fill" : "arrow.right.square") ?? "Toggle toolbar")
                }
            }
            HStack {
                if showToolBar {
                    HStack {
                        if isMaster {
                            Button {
                                withAnimation { model.toggleDisplayMode() }
                            } label: {
                                Image(systemName: model.iconDisplayMode)
                                    .contentTransition(.symbolEffect(.replace.byLayer))
                                    .frame(width: 28, height: 24)
                                    .accessibilityLabel(AccessibilityLabelCache.shared.label(for: model.iconDisplayMode) ?? "Display mode")
                            }

                            barButtonViews

                            if appWindowSizeModel.mode == .regular {
                                hideScaleButtonView

                                reshareButtonView

                                hexMapScaleView
                                pinScaleView
                            }
                            Spacer()
                            if appWindowSizeModel.mode == .compact {
                                hideScaleButtonView
                                reshareButtonView
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
        .animation(.bouncy.delay(hideScales ? 0 : 0.25), value: showToolBar)
        .buttonStyle(.borderedProminent)
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
            withAnimation(.bouncy) {
                root.editController.addMonsters(map: map, entryId: nil, location: nil, monsters: monsters, number: 1)
            }
            if model.isStreaming { model.sendMapUpdates?() }
            selectedPin.resetSelection(itemId: nil, entryId: nil)
        }
    }

    @ViewBuilder
    var barButtonViews: some View {
        Button {
            withAnimation { model.isStreaming.toggle() }
        } label: {
            let symbolName = "person.2\(model.isStreaming ? ".fill" : ".slash")"
            Image(systemName: symbolName)
                .contentTransition(.symbolEffect(.replace.wholeSymbol))
                .frame(height: 24)
                .accessibilityLabel(AccessibilityLabelCache.shared.label(for: symbolName) ?? "Streaming")
        }

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
                .accessibilityLabel(AccessibilityLabelCache.shared.label(for: symbolName) ?? "Pin selection")
        }
        .matchedTransitionSource(id: "gamePin", in: pinSpace)

        Button {
            withAnimation { model.isPointing.toggle() }
        } label: {
            let symbolName = "hand.point.up.left\(model.isPointing ? ".fill" : "")"
            Image(systemName: symbolName)
                .contentTransition(.symbolEffect(.replace.offUp))
                .frame(height: 24)
                .accessibilityLabel(AccessibilityLabelCache.shared.label(for: symbolName) ?? "Pointing")
        }
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
#endif
        }
        .opacity(hideScales ? 0 : 1)
    }

    @ViewBuilder
    var hexMapScaleView: some View {
        @Bindable var model = model
        HStack {
#if !os(tvOS)
            Button {
                withAnimation {
                    let map = root.gameController.currentItem()
                    let _ = editController.toggleHexMap(for: map)
                    model.hexScale = map.hexMapScale
                    model.isHexMap = map.entries.contains(where: { $0.isHexGrid })
                }
            } label: {
                let symbolName = model.isHexMap ? "hexagon.fill" : "hexagon"
                Image(systemName: symbolName)
                    .contentTransition(.symbolEffect(.replace.wholeSymbol))
                    .frame(width: 24, height: 24)
                    .accessibilityLabel(AccessibilityLabelCache.shared.label(for: symbolName) ?? "Hex map")
            }
            Text("Hex Map Scale", bundle: .module)

            Slider(value: $model.hexScale, in: 20 ... 200) {
                Text("Hex Map Scale", bundle: .module)
            }
            .labelsHidden()
#endif
        }
        .opacity(hideScales ? 0 : 1)
    }

    @ViewBuilder
    var hideScaleButtonView: some View {
        Button {
            hideScales.toggle()
        } label: {
            let symbolName = "square.arrowtriangle.4.outward"
            Image(systemName: symbolName)
                .frame(width: 24, height: 24)
                .accessibilityLabel(AccessibilityLabelCache.shared.label(for: symbolName) ?? "Toggle scales")
        }
    }

    @ViewBuilder
    var reshareButtonView: some View {
        Button {
            guard let mapId = root.gameController.gameModel.currentItemId else { return }
            Task {
                await networkActions?.shareId(root.gameController.share(id: mapId))
            }
            withAnimation {
                model.resetReshare()
            }
        } label: {
            let symbolName = "square.and.arrow.up"
            Image(systemName: symbolName)
                .frame(width: 24, height: 24)
                .accessibilityLabel(AccessibilityLabelCache.shared.label(for: symbolName) ?? "Share")
        }
        .disabled(!model.canReshare)
        .opacity(hideScales ? 0 : 1)
    }
}

#Preview {
    @Previewable var editController: EditController = .preview
    @Previewable var editorModel = MapEditorModel(
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
