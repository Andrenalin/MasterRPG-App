// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DisplayConfigEditor: View {
    let model: MapModel
    let constTime = Date.now
    
    @Environment(MapRootModel.self) private var root
    
    @State private var isAnimating = false
    @State private var showTileEditor = false
    
    @State private var color = Color.black
    @State private var borderToggleEditModel: EditIdentifierModel<Bool> = EditIdentifierModel(value: false)
    
    var body: some View {
        Section {
#if !os(tvOS)
            coverColorView
            
            activateBorderView
            
            DisplayConfigBorderEditor(model: model)
                .disabled(!model.displayConfig.hasBorder)
#endif
        } header: {
            Text("Config", bundle: .module)
        }
        .onChange(of: model.id, initial: true) {
            resetColor()
            updateToggleValue()
        }
    }
    
#if !os(tvOS)
    @ViewBuilder var coverColorView: some View {
        LabeledContent {
            ColorPicker(selection: $color, supportsOpacity: false) {
                Text("Cover color", bundle: .module)
            }
            .labelsHidden()
            .tint(root.configurable.module.tint)
        } label: {
            Text("Cover color", bundle: .module)
        }
        .onChange(of: color) {
            saveColor()
        }
        .onChange(of: model.displayConfig.color) {
            resetColor()
        }
    }
    
    private func resetColor() {
        color <=> model.displayConfig.color
    }

    private func saveColor() {
        root.editController.reset(coverColor: color, itemId: model.id)
    }
#endif
    
    @ViewBuilder var activateBorderView: some View {
        ToggleEditor(model: borderToggleEditModel, title: "Activate Border", bundle: .module, icon: "rectangle")
            .onChange(of: model.displayConfig.hasBorder) {
                updateToggleValue()
            }
    }
    
    func updateToggleValue() {
        let toggleValue = model.displayConfig.hasBorder
        if model.id != borderToggleEditModel.valueId || toggleValue != borderToggleEditModel.value {
            let editController = root.editController
            borderToggleEditModel.reset(valueId: model.id, value: toggleValue) { itemId, value in
                editController.reset(hasBorder: value, itemId: itemId)
            }
        }
    }
}
