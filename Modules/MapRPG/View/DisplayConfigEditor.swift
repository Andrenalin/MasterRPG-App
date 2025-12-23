// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DisplayConfigEditor: View {
    let editController: EditController
    let constTime = Date.now
    
    @Environment(MapRootModel.self) private var root
    
    @State private var isAnimating = false
    @State private var showTileEditor = false
    
    var body: some View {
        @Bindable var model = editController.model
        Section {
#if !os(tvOS)
            LabeledContent {
                ColorPicker(selection: $model.displayConfig.color, supportsOpacity: false) {
                    Text("Cover color", bundle: .module)
                }
                .labelsHidden()
                .tint(root.module.tint)
            } label: {
                Text("Cover color", bundle: .module)
            }
            
            LabeledContent {
                Toggle(isOn: $model.displayConfig.hasBorder) {
                    Label { Text("Activate Border", bundle: .module) } icon: { Image(systemName: "rectangle") }
                }
                .labelsHidden()
                .tint(root.module.tint)
            } label: {
                Text("Activate Border", bundle: .module)
            }
            
            DisplayConfigBorderEditor(editController: editController)
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
        RootEditCanvasMap(editController: editController, tile: .empty)
    }
}

struct DisplayConfigBorderEditor: View {
    let editController: EditController
    @Environment(MapRootModel.self) private var root
    
    var body: some View {
        @Bindable var model = editController.model
        Group {
            LabeledContent {
#if !os(tvOS)
                ColorPicker(selection: $model.displayConfig.borderColor) {
                    Text("Border color", bundle: .module)
                }
                .labelsHidden()
                .tint(root.module.tint)
#else
                Text("Color Picker not available", bundle: .module)
#endif
            } label: {
                Text("Border color", bundle: .module)
            }
            
            TextDoubleEditor(editController: editController, model: $model.displayConfig.borderThicknessDouble, title: "Thickness", icon: "slider.horizontal.below.square.and.square.filled", prompt: "Thickness of the border", bundle: .module, range: 0...25)
        }
    }
}
