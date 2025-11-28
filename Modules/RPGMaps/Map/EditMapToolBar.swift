// @copyright André Trettin

import AndrenalinKit
import PhotoRPG
import SwiftUI
import CharacterRPG

@Observable
final class EditToolBarModel {
    init(pinScale: CGFloat = 1, hexScale: Double = 1, hideCloseButton: Bool = false, displayMode: MapDisplayMode = .master) {
        self.pinScale = pinScale
        self.hexScale = hexScale
        self.hideCloseButton = hideCloseButton
        self.displayMode = displayMode
    }
    
    var pinScale: CGFloat = 1
    var hexScale: Double = 1
    
    var hideCloseButton: Bool = false
    
    var displayMode: MapDisplayMode = .master
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
}

struct EditToolBar: View {
    let editController: EditController
    let model: EditToolBarModel
    let closeAction: (() -> Void)?
    
    @Environment(MapRootModel.self) private var root
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wideMode) private var wideMode
    
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif
    @State private var pinScale: CGFloat = 1
    @State private var hexScale: Double = 1
    
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
                Button {
                    withAnimation { showToolBar.toggle() }
                } label: {
                    Image(systemName: showToolBar ? "arrow.left.square.fill" : "arrow.right.square")
                        .contentTransition(.symbolEffect(.replace.downUp))
                        .frame(height: 24)
                }
                
                HStack {
                    if showToolBar {
                        HStack {
                            Button {
                                withAnimation { model.toggleDisplayMode() }
                            } label: {
                                Image(systemName: model.iconDisplaMode)
                                    .contentTransition(.symbolEffect(.replace.byLayer))
                                    .frame(width: 28, height: 24)
                            }
                            
                            barButtonViews
                            
                            if wideMode != .small {
                                hexMapScaleView
                                pinScaleView
                            }
                            Spacer()
                            if wideMode == .small {
                                hideScaleButtonView
                            }
                            closeButtonView
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
        .onChange(of: model.pinScale, initial: true) {
            pinScale <=> model.pinScale
        }
    }
    
    @ViewBuilder
    var barButtonViews: some View {
        if model.hideCloseButton {
            Button {
#if os(macOS)
                openWindow(id: NetworkModules.value.linkWindowId)
#else
                showPinSelection.toggle()
#endif
            } label: {
                Image(systemName: "mappin\(showPinSelection ? ".and.ellipse" : "")")
                    .contentTransition(.symbolEffect(.replace.wholeSymbol))
                    .frame(width: 24, height: 24)
            }
#if !os(macOS)
            .sizedSheet(isPresented: $showPinSelection) {
                root.valueRoot.viewController.viewSelect(root: root.valueRoot, filter: .monster, isGroupHidden: true) {
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
        }
    }
    
    @ViewBuilder
    var pinScaleView: some View {
        @Bindable var model = model
        HStack {
#if !os(tvOS)
            Text("Pin Scale", bundle: .module)
            
            Slider(value: $pinScale, in: 0.5 ... 3.5) {
                Text("Pin Scale", bundle: .module)
            }
            .onChange(of: pinScale) {
                model.pinScale = pinScale
            }
            .labelsHidden()
#endif
        }
        .opacity(model.hideCloseButton ? 0 : 1)
    }
    
    @ViewBuilder
    var hexMapScaleView: some View {
        @Bindable var model = model
        HStack {
#if !os(tvOS)
            Button {
                withAnimation {
                    let _ = editController.toggleHexMap()
                }
            } label: {
                Image(systemName: editController.isHexMap() ? "hexagon.fill" : "hexagon")
                    .contentTransition(.symbolEffect(.replace.wholeSymbol))
                    .frame(width: 24, height: 24)
            }
            Text("Hex Map Scale", bundle: .module)
            
            Slider(value: $hexScale, in: 20 ... 200) {
                Text("Hex Map Scale", bundle: .module)
            }
            .onChange(of: hexScale) {
                model.hexScale = hexScale
            }
            .labelsHidden()
#endif
        }
        .opacity(model.hideCloseButton ? 0 : 1)
    }
    
    @ViewBuilder
    var closeButtonView: some View {
        if !model.hideCloseButton {
            Button {
                if let closeAction {
                    closeAction()
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark.circle")
                    .frame(width: 24, height: 24)
            }
        }
    }
    
    @ViewBuilder
    var hideScaleButtonView: some View {
        if !model.hideCloseButton {
            Button {
                hideScales.toggle()
            } label: {
                Image(systemName: "square.arrowtriangle.4.outward")
                    .frame(width: 24, height: 24)
            }
        }
    }
}

#Preview {
    VStack {
        Spacer()
        
        HStack {
            EditToolBar(editController: .preview, model: EditToolBarModel()) {
                print("Close")
            }
            .environment(MapRootModel.preview)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .setWideMode()
}
