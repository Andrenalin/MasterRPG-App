// @copyright André Trettin

import AndrenalinKit
import RoleGameKit
import SwiftUI
import RPGValues
import RPGWeathers
import RPGMaps
import RPGAdventures
import RPGPhotos

struct SaveAction: View {
    let appModel: AppStore
    let inputModel: InputModel
    let imageListModel: ImageListModel
    let moduleChooserModel: ModuleChooserModel
    let closeAction: () -> Void

    var body: some View {
        Button {
            Task {
                var photoIds: [UUID] = []
                var photoLinks: [String] = []
                for image in imageListModel.images {
                    let (id, link) = await appModel.photoRoot.addNewPhoto(data: image.imageData, name: inputModel.name, text: inputModel.text)
                    photoIds.append(id)
                    photoLinks.append(link)
                }
                switch moduleChooserModel.currentModule {
                case .map:
                    await appModel.mapRoot.addNewMap(name: inputModel.name, text: inputModel.text, photoId: photoIds.first)
                case .adventure:
                    await appModel.adventureRoot.addNewAdventure(name: inputModel.name, text: inputModel.text, photoIds: photoIds, photoLinks: photoLinks)
                case .weather:
                    await appModel.weatherRoot.addNewWeather(name: inputModel.name, text: inputModel.text, photoId: photoIds.first)
                case .value:
                    await appModel.valueRoot.addNewValue(name: inputModel.name, text: inputModel.text, photoIds: photoIds)
                default:
                    break
                }
                
                
                await appModel.save()
                closeAction()
            }
        } label: {
            Text("Save")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(disableSave)
    }
    
    private var disableSave: Bool {
        !appModel.hasDatabase || inputModel.name.isEmpty
    }
}
