// @copyright André Trettin

import CoreRPG
import SwiftUI
import CharacterRPG

@Observable
final class GameToolBarModel {
    var isStreaming: Bool = false
    var isPointing: Bool = false

    var pinScale: CGFloat = 1
    var hexScale: Double = 1

    var lastPinScale: CGFloat = 1
    var lastHexScale: Double = 1

    var hideCloseButton: Bool = true

    var displayMode: MapDisplayMode = .player
    func toggleDisplayMode() {
        displayMode =
        switch displayMode {
        case .master: .player
        case .player: .reader
        case .reader: .master
        }
    }
    var iconDisplaMode: String {
        switch displayMode {
        case .master: "rectangle.3.offgrid.fill"
        case .player: "rectangle.lefthalf.inset.filled"
        case .reader: "rectangle.3.offgrid"
        }
    }

    func resetScales(from map: MapModel) {
        pinScale = map.pinScale
        hexScale = map.hexMapScale
        resetReshare()
    }

    func resetReshare() {
        lastPinScale = pinScale
        lastHexScale = hexScale
    }

    var canReshare: Bool {
        lastHexScale != hexScale || lastPinScale != pinScale
    }
}

struct GameToolBar: View {
    let editController: EditController
    let model: GameToolBarModel
    let isMaster: Bool
    
    @Environment(MapRootModel.self) private var root
    @Environment(\.dismiss) private var dismiss
    @Environment(\.networkActions) private var networkActions
    @Environment(\.wideMode) private var wideMode
    
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif
    
    @State private var showPinSelection: Bool = false
    @State private var pinSelection: [UUID] = []
    
    @State private var showToolBar: Bool = true
    @State private var hideScales: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if wideMode == .small {
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
                }
            }
            HStack {
                if showToolBar {
                    HStack {
                        if isMaster {
                            Button {
                                withAnimation { model.toggleDisplayMode() }
                            } label: {
                                Image(systemName: model.iconDisplaMode)
                                    .contentTransition(.symbolEffect(.replace.byLayer))
                                    .frame(width: 28, height: 24)
                            }
                            
                            barButtonViews

                            if wideMode != .small {
                                hideScaleButtonView

                                reshareButtonView

                                hexMapScaleView
                                pinScaleView
                            }
                            Spacer()
                            if wideMode == .small {
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
    }
    
    @ViewBuilder
    var barButtonViews: some View {
        Button {
            withAnimation { model.isStreaming.toggle() }
        } label: {
            Image(systemName: "person.2\(model.isStreaming ? ".fill" : ".slash")")
                .contentTransition(.symbolEffect(.replace.wholeSymbol))
                .frame(height: 24)
        }
        
        Button {
#if os(macOS)
            openWindow(id: NetworkModules.value.linkWindowId)
#else
            showPinSelection.toggle()
#endif
        } label: {
            Image(systemName: "mappin\(showPinSelection ? ".and.ellipse" : "")")
                .frame(width: 24, height: 24)
        }
#if !os(macOS)
        .sizedSheet(isPresented: $showPinSelection) {
            root.characterRoot.viewController.viewSelect(root: root.characterRoot, filter: .monster, isGroupHidden: true) {
                return pinSelection.map { ItemRowModel(itemId: $0, typeId: .value) }
            } toggleSelection: { selection, _ in
                if pinSelection.contains(selection.itemId) {
                    pinSelection.removeAll(where: { selection.itemId == $0 })
                } else {
                    pinSelection.append(selection.itemId)
                }
            } dismissAction: {
                withAnimation { showPinSelection = false }
            }
        }
        .onChange(of: showPinSelection, initial: false) {
            guard !showPinSelection, !pinSelection.isEmpty else { return }
            let map = root.gameController.currentItem()
            let entry = map.entries.reversed().first(where: { $0.isShown })
            withAnimation { editController.addMonsters(map: map, entryId: entry?.id, location: nil, monsters: pinSelection.map { ItemRowModel(itemId: $0, typeId: .value)}, number: 1) }
            pinSelection = []
        }
#endif
        
        Button {
            withAnimation { model.isPointing.toggle() }
        } label: {
            Image(systemName: "hand.point.up.left\(model.isPointing ? ".fill" : "")")
                .contentTransition(.symbolEffect(.replace.offUp))
                .frame(height: 24)
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
                }
            } label: {
                Image(systemName: editController.isHexMap() ? "hexagon.fill" : "hexagon")
                    .contentTransition(.symbolEffect(.replace.wholeSymbol))
                    .frame(width: 24, height: 24)
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
            Image(systemName: "square.arrowtriangle.4.outward")
                .frame(width: 24, height: 24)
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
            Image(systemName: "square.and.arrow.up")
                .frame(width: 24, height: 24)
        }
        .disabled(!model.canReshare)
        .opacity(hideScales ? 0 : 1)
    }

}


#Preview {
    HStack {
        GameToolBar(editController: .preview, model: GameToolBarModel(), isMaster: true)
            .environment(MapRootModel.preview)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
