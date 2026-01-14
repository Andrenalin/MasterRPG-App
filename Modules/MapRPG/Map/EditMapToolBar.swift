// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI
import CharacterRPG

@Observable
final class EditToolBarModel {
    init(mapModel: MapModel, pinScale: CGFloat = 1, hexScale: Double = 1, hideCloseButton: Bool = false, displayMode: MapDisplayMode = .master) {
        self.mapModel = mapModel
        self.pinScale = pinScale
        self.hexScale = hexScale
        self.hideCloseButton = hideCloseButton
        self.displayMode = displayMode
    }
    
    var mapModel: MapModel?
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

struct EditToolBarViewModifier: ViewModifier {
    let editController: EditController
    let model: EditToolBarModel
    
    @Environment(\.dismiss) private var dismiss
    #if !os(tvOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @Environment(MapRootModel.self) private var root
    
    @State private var hideScales: Bool = true
    @State private var showPinSelection: Bool = false
    
    @State private var pinScale: CGFloat = 1
    @State private var hexScale: Double = 1
    
    @State private var selectedPin: ItemSelectionModel = ItemSelectionModel(isSingleSelection: false, allowCollections: true)
    
    @Namespace private var pinSpace
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                GlassEffectContainerView {
                    VStack(spacing: 8) {
                        pinScaleView
                        
                        hexMapScaleView
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
                root.viewController.characterSelection(root: root, selectionModel: selectedPin)
#if !os(macOS)
                .navigationTransition(.zoom(sourceID: "pin", in: pinSpace))
#endif
            }
            .onChange(of: model.pinScale, initial: true) {
                pinScale <=> model.pinScale
            }
            .onChange(of: model.hexScale, initial: true) {
                hexScale <=> model.hexScale
            }
            .onChange(of: showPinSelection, initial: false) {
                guard !showPinSelection, !selectedPin.selection.isEmpty, let mapModel = model.mapModel else { return }
                let entryId = editController.editorModel.currentEntryId
                withAnimation { editController.addMonsters(map: mapModel, entryId: entryId, location: nil, monsters: selectedPin.selection.map { ItemRowModel(itemId: $0.itemId, typeId: .value) }, number: 1) }
                selectedPin.resetSelection(itemId: nil, entryId: nil)
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
                    toggleDisplayModeButton
                    hexCreationButton
                    
                    showPinSelectionButton
                        .matchedTransitionSource(id: "pin", in: pinSpace)
                }
                
#if !os(visionOS) && !os(tvOS)
                ToolbarSpacer(.flexible, placement: bottomBarPlacement)
#endif

#if !os(macOS)
                ToolbarItem(placement: bottomBarPlacement) {
                    closeButtonView
                }
#endif
            }
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
    
    var navTitle: String {
        guard editController.editorModel.currentEntryId != nil else { return titlename }
        return subtitleName
    }
    
    var titlename: String {
        model.mapModel?.name ?? "Untitled"
    }
    
    var subtitleName: String {
        guard let mapModel = model.mapModel else { return "" }
        guard let entryId = editController.editorModel.currentEntryId else { return "\(editController.editEntries(for: mapModel).count) Entries" }
        let current: String
        if let currentIndex {
            current = "\(currentIndex + 1)/"
        } else {
            current = ""
        }
        return "\(mapModel[entryId].name) \(current)\(editController.editEntries(for: mapModel).count)"
    }
    
    @ViewBuilder var nextEntryButton: some View {
        Button {
            resetSelectedIndex(shouldIncrease: true)
        } label: {
            Image(systemName: canIncrease ? "forward" : "plus")
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
        }
    }
    
    @ViewBuilder var previousEntryButton: some View {
        Button {
            resetSelectedIndex(shouldIncrease: false)
        } label: {
            Image(systemName: "backward")
        }
    }
    
    @ViewBuilder var closeButtonView: some View {
        if !model.hideCloseButton {
            Button {
                dismiss()
            } label: {
                Image(systemName: "checkmark")
            }
        }
    }
    
    @ViewBuilder var showPinSelectionButton: some View {
        Button {
#if os(macOS)
            openWindow(id: NetworkModules.value.linkWindowId)
#else
            showPinSelection.toggle()
#endif
        } label: {
            Image(systemName: "mappin\(showPinSelection ? ".and.ellipse" : "")")
                .contentTransition(.symbolEffect(.replace.wholeSymbol))
        }
    }
    
    @ViewBuilder var toggleDisplayModeButton: some View {
        Button {
            withAnimation { model.toggleDisplayMode() }
        } label: {
            Image(systemName: model.iconDisplaMode)
                .contentTransition(.symbolEffect(.replace.byLayer))
        }
    }
    
    @ViewBuilder var hideScaleButton: some View {
        if !model.hideCloseButton {
            Button {
                hideScales.toggle()
            } label: {
                Image(systemName: "square.arrowtriangle.4.outward")
            }
        }
    }
    
    @ViewBuilder var hexCreationButton: some View {
        Button {
            guard let mapModel = model.mapModel else { return }
            withAnimation {
                let _ = editController.toggleHexMap(for: mapModel)
                withAnimation { hideScales <=> false }
            }
        } label: {
            Image(systemName: editController.isHexMap(for: model.mapModel ?? MapModel.empty) ? "hexagon.fill" : "hexagon")
                .contentTransition(.symbolEffect(.replace.wholeSymbol))
        }
    }
    
    @ViewBuilder var pinScaleView: some View {
        @Bindable var model = model
        HStack {
#if !os(tvOS)
            Text("Pin Scale", bundle: .module)
                .foregroundStyle(.white)
            
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
    
    @ViewBuilder var hexMapScaleView: some View {
        @Bindable var model = model
        HStack {
#if !os(tvOS)
            Text("Hex Scale", bundle: .module)
                .foregroundStyle(.white)
            
            Slider(value: $hexScale, in: 20 ... 200) {
                Text("Hex Scale", bundle: .module)
            }
            .onChange(of: hexScale) {
                model.hexScale = hexScale
            }
            .labelsHidden()
#endif
        }
        .opacity(model.hideCloseButton ? 0 : 1)
    }
    
    func resetSelectedIndex(shouldIncrease: Bool) {
        guard let mapModel = model.mapModel else { return }
        if shouldIncrease && !canIncrease {
            let entryId = editController.addNewEntry(itemId: mapModel.id)
            withAnimation { editController.editorModel.currentEntryId = entryId }
            return
        }
        
        guard editController.editorModel.currentEntryId != nil else {
            
            if let first = editController.editEntries(for: mapModel).first {
                withAnimation { editController.editorModel.currentEntryId = first.id }
            }
            return
        }
        guard let index = currentIndex else { return }
        
        let nextIndex = shouldIncrease ? index.advanced(by: 1) : index.advanced(by: -1)
        if nextIndex >= 0 && nextIndex < editController.editEntries(for: mapModel).count {
            withAnimation { editController.editorModel.currentEntryId = editController.editEntries(for: mapModel)[nextIndex].id }
        }
    }
    
    var canIncrease: Bool {
        guard let mapModel = model.mapModel else { return false }
        guard editController.editorModel.currentEntryId != nil else {
            return !editController.editEntries(for: mapModel).isEmpty
        }
        
        guard let index = currentIndex else { return false }
        
        return index + 1 < editController.editEntries(for: mapModel).count
    }
    
    var currentIndex: Int? {
        guard let mapModel = model.mapModel else { return nil }
        guard let entryId = editController.editorModel.currentEntryId else { return nil }
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

#Preview("New Modifier") {
    @Previewable var model = EditToolBarModel(mapModel: .empty)
    @Previewable var editController: EditController = .preview
    
    NavigationStack {
        VStack {
            Rectangle().fill(Color.green.gradient).ignoresSafeArea()
        }
        .modifier(EditToolBarViewModifier(editController: editController, model: model))
    }
    .setAppSizeMode()
}
