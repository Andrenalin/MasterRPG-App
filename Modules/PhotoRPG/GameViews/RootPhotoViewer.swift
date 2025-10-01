// @copyright André Trettin

import CoreRPG
import SwiftUI

struct RootPhotoViewer: View {
    let model: ItemDataCodableModel?
    let toolBarModel: GameToolBarModel
    var isGame: Bool = false
    var dismiss: (() -> Void)? = nil

    @Environment(PhotoRootModel.self) private var root
    @Environment(\.dismiss) private var dismissModal
    
#if os(visionOS)
    @Environment(\.openImmersiveSpace) private var openSpace
    @Environment(\.dismissImmersiveSpace) private var dismissSpace
#endif

    var body: some View {
        let _ = Self._printChanges()
        GeometryReader { geo in
            if let photoModel {
                RootImageViewer(model: photoModel, size: geo.size, toolBarModel: toolBarModel, isGame: isGame) {
                    if let dismiss {
                        dismiss()
                    } else {
                        dismissModal()
                    }
                }
            }
        }
        .onChange(of: root.gameController.photoGameModel.openPhotoSpace, initial: false) {
#if os(visionOS)
            Task {
                if root.gameController.photoGameModel.openPhotoSpace {
                    await openSpace(id: "PhotoWorld", value: PhotoWorldSelection(id: model.id, rotationDegrees: 67))
                } else {
                    await dismissSpace()
                }
            }
#endif
        }
    }
    
    var photoModel: ItemDataModel? {
        guard let model else { return nil }
        return ItemDataModel(codableModel: model)
    }
}

//#Preview {
//    RootPhotoViewer(model: PhotoModel.preview, toolBarModel: GameToolBarModel(), isGame: true)
//        .environment(PhotoRoot.previewWithData)
//}
