// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DisplayConfigBorderEditor: View {
    let model: MapModel
    @Environment(MapRootModel.self) private var root
    
    @State private var borderThicknessModel = EditIdentifierModel(value: 0.0)
    @State private var color = Color.red
    
    var body: some View {
        Group {
            LabeledContent {
#if !os(tvOS)
                ColorPicker(selection: $color) {
                    Text("Border color", bundle: .module)
                }
                .labelsHidden()
                .moduleTint(root.configurable.module)
#else
                Text("Color Picker not available", bundle: .module)
#endif
            } label: {
                Text("Border color", bundle: .module)
            }
            
            TextDoubleEditor(model: borderThicknessModel, title: "Thickness", icon: "slider.horizontal.below.square.and.square.filled", prompt: "Thickness of the border", bundle: .module, range: 0...25)
        }
        .onChange(of: model.id, initial: true) {
            resetBorderValue()
            resetColor()
        }
        .onChange(of: model.displayConfig.borderThicknessDouble) {
            resetBorderValue()
        }
        .onChange(of: model.displayConfig.border.color) {
            resetColor()
        }
        .onChange(of: color) {
            saveColor()
        }
    }

    private func saveColor() {
        root.editController.reset(borderColor: color, itemId: model.id)
    }

    private func resetColor() {
        guard color != model.displayConfig.border.color else { return }
        color <=> model.displayConfig.border.color
    }
    
    private func resetBorderValue() {
        if borderThicknessModel.valueId != model.id || borderThicknessModel.value != model.displayConfig.borderThicknessDouble {
            let editController = root.editController
            borderThicknessModel.reset(valueId: model.id, value: model.displayConfig.borderThicknessDouble) { itemId, value in
                editController.reset(borderThickness: value, itemId: itemId)
            }
        }
    }
}

#Preview(traits: .mockData) { DisplayConfigBorderEditor(model: .preview) }
