// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DisplayConfigEditor: View {
    let model: MapModel
    let constTime = Date.now
    
    @Environment(MapRootModel.self) private var root
    
    @State private var isAnimating = false
    @State private var showTileEditor = false
    
    @State private var borderToggleEditModel: EditIdentifierModel<Bool> = EditIdentifierModel(value: false)
    
    var body: some View {
        @Bindable var model = model
        Section {
#if !os(tvOS)
            LabeledContent {
                ColorPicker(selection: $model.displayConfig.color, supportsOpacity: false) {
                    Text("Cover color", bundle: .module)
                }
                .labelsHidden()
                .tint(root.configurable.module.tint)
            } label: {
                Text("Cover color", bundle: .module)
            }
            
            activateBorderView
            
            DisplayConfigBorderEditor(model: model)
                .disabled(!model.displayConfig.hasBorder)
#endif
        } header: {
#if os(macOS)
            Divider()
                .padding(.top)
#endif
            configHeaderView
        }
        .sheetFullScreen(isPresented: $showTileEditor, idealSize: model.mapIdealSize) {
            tileEditorView
        }
    }
    
    @ViewBuilder var activateBorderView: some View {
        ToggleEditor(model: borderToggleEditModel, title: "Activate Border", bundle: .module, icon: "rectangle")
            .onChange(of: model, initial: true) {
                updateToggleValue()
            }
            .onChange(of: model.displayConfig.hasBorder) {
                updateToggleValue()
            }
    }
    
    func updateToggleValue() {
        let toggleValue = model.displayConfig.hasBorder
        guard model.id != borderToggleEditModel.valueId || toggleValue != borderToggleEditModel.value else { return }
        let editController = root.editController
        borderToggleEditModel.reset(valueId: model.id, value: toggleValue) { itemId, value in
            guard let item = editController.editModel(for: itemId) else { return }
            if value != item.displayConfig.hasBorder {
                item.displayConfig.hasBorder = value
                editController.save(updated: item, message: String(localized: "toggle border").localizedString)
            }
        }
    }
    
    var configHeaderView: some View {
        HStack {
            Text("Config", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
            
            Button {
                withAnimation { showTileEditor.toggle() }
            } label: {
                Label { Text("Edit Tile", bundle: .module) } icon: { Image(systemName: "skew") }
            }
        }
    }
    
    var tileEditorView: some View {
        RootEditCanvasMap(itemId: model.id, tile: .empty)
    }
}

struct DisplayConfigBorderEditor: View {
    let model: MapModel
    @Environment(MapRootModel.self) private var root
    
    @State private var borderThicknessModel = EditIdentifierModel(value: 0.0)
    
    var body: some View {
        @Bindable var model = model
        Group {
            LabeledContent {
#if !os(tvOS)
                ColorPicker(selection: $model.displayConfig.borderColor) {
                    Text("Border color", bundle: .module)
                }
                .labelsHidden()
                .tint(root.configurable.module.tint)
#else
                Text("Color Picker not available", bundle: .module)
#endif
            } label: {
                Text("Border color", bundle: .module)
            }
            
            TextDoubleEditor(model: borderThicknessModel, title: "Thickness", icon: "slider.horizontal.below.square.and.square.filled", prompt: "Thickness of the border", bundle: .module, range: 0...25)
        }
        .onChange(of: model.id, initial: true) {
            let editController = root.editController
            borderThicknessModel.reset(valueId: model.id, value: model.displayConfig.borderThicknessDouble) { itemId, value in
                editController.reset(borderThickness: value, itemId: itemId)
            }
        }
    }
}
