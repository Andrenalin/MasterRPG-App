// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DisplayConfigEditor: View {
    let model: MapModel
    
    @Environment(MapRootModel.self) private var root
    
    @State private var color = Color.black
    @State private var borderToggleEditModel: EditIdentifierModel<Bool> = EditIdentifierModel(value: false)
    
    var body: some View {
        Section {
#if !os(tvOS)
            coverColorView
            
            activateBorderView
            
            if model.displayConfig.hasBorder {
                DisplayConfigBorderEditor(model: model)
            }
#endif
        } header: {
            Text("Config", bundle: .module)
        }
        .animation(.default, value: model.displayConfig.hasBorder)
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
#endif

    private func resetColor() {
        color <=> model.displayConfig.color
    }

    private func saveColor() {
        root.editController.reset(coverColor: color, itemId: model.id)
    }

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
