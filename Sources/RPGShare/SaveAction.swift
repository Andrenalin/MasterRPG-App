// @copyright André Trettin

import AndrenalinKit
import RoleGameKit
import SwiftUI

struct SaveAction: View {
    let appStore: AppStore
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
                    let (id, link) = await appStore.photoRoot.addNewPhoto(data: image.imageData, name: inputModel.name, text: inputModel.text)
                    photoIds.append(id)
                    photoLinks.append(link)
                }
                switch moduleChooserModel.currentModule {
                case .map:
                    await appStore.mapRoot.addNewMap(name: inputModel.name, text: inputModel.text, photoId: photoIds.first)
                case .adventure:
                    await appStore.adventureRoot.addNewAdventure(name: inputModel.name, text: inputModel.text, photoIds: photoIds, photoLinks: photoLinks)
                case .weather:
                    await appStore.weatherRoot.addNewWeather(name: inputModel.name, text: inputModel.text, photoId: photoIds.first)
                case .value:
                    await appStore.valueRoot.addNewValue(name: inputModel.name, text: inputModel.text, photoIds: photoIds)
                default:
                    break
                }
                
                
                await appStore.save()
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
        !appStore.hasDatabase || inputModel.name.isEmpty
    }
}
