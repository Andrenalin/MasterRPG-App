// @copyright André Trettin

import AndrenalinKit
import SwiftUI

@Observable
final class ModuleChooserModel {
    var currentModule: NetworkModules = .adventure
    var supportedModules: [NetworkModules] = [.adventure, .value, .map, .photo, .weather]
    
    var hasPhotos = false
    
    var showPhotoWarning = false
}

struct ModuleChooserView: View {
    let model: ModuleChooserModel
    
    var body: some View {
        @Bindable var model = model
        Picker(selection: $model.currentModule) {
            ForEach(model.supportedModules, id: \.self) { module in
                Label {
                    Text(module.localizedTitle)
                } icon: {
                    Image(systemName: module.icon)
                }
            }
        } label: {
            Text("Module")
        }
        .onChange(of: model.currentModule, initial: true) {
            updatePhotoWarning()
        }
        .onChange(of: model.hasPhotos, initial: false) {
            updatePhotoWarning()
        }

        if model.showPhotoWarning {
            Text("All photos will be created in Photo module. The selected module will create one item that will reference them.")
                .foregroundStyle(.red)
                .transition(.scale)
        }
    }
    
    func updatePhotoWarning() {
        if model.hasPhotos && model.currentModule != .photo {
            model.showPhotoWarning = true
        } else {
            model.showPhotoWarning = false
        }
    }
}

extension ModuleChooserModel {
    @MainActor
    static let preview = ModuleChooserModel()
}
