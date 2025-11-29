// @copyright André Trettin

import CoreRPG
import SwiftUI

struct PhotoOrientationEditor: View {
    let editController: EditController
    
    @Environment(PhotoRootModel.self) private var root

    @State private var degrees: Double = 0.0

    var body: some View {
        LabeledContent {
            Picker(selection: $degrees) {
                Text("0", bundle: .module).tag(0.0)
                Text("90", bundle: .module).tag(90.0)
                Text("180", bundle: .module).tag(180.0)
                Text("270", bundle: .module).tag(270.0)
            } label: {
                Text("Orientation", bundle: .module)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        } label: {
            Text("Orientation", bundle: .module)
        }
        .onChange(of: editController.model, initial: true) {
            withAnimation { degrees = editController.model.degrees }
        }
        .onChange(of: degrees) {
            if editController.model.degrees != degrees {
                editController.model.degrees = degrees
                editController.save(with: String(localized: "Rotate to \(degrees)").localizedString)
            }
        }
    }
}

#Preview {
    PhotoOrientationEditor(editController: .preview)
        .environment(PhotoRootModel.preview)
}
