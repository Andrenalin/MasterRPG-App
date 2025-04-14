// @copyright André Trettin

import AndrenalinKit
import SwiftUI

@MainActor
struct CharacterSheet: View {
    let model: ValueModel
    let showTopImage: Bool
    let dismissAction: (() -> Void)?
    
    @Environment(ValueRoot.self) private var root

    @State private var sheetModel: SheetModel = SheetModel(id: UUID(), name: "", description: "", groups: [])
    
    var body: some View {
        TableRootSheet(linkControllable: root.rootControllable.linkControllable, model: sheetModel, showImage: showTopImage, dismissAction: dismissAction, imageContent: imageView(size:))
            .onChange(of: model, initial: true) {
                resetModels()
            }
    }

    func resetModels() {
        withAnimation {
            sheetModel = SheetController(root: root).sheet(for: model.id)
        }
    }
}

private extension CharacterSheet {
    func imageView(size: CGSize) -> some View {
        root.photoRoot.viewController.photoView(for: model.photoId, useGame: false) { image, photoDegrees in
            Image(akImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .rotationEffect(Angle(degrees: photoDegrees))
                .clipShape(.rect(cornerRadius: 16))
                .frame(width: size.width, height: size.height, alignment: .center)
        }
    }
}

#Preview {
    CharacterSheet(model: .preview, showTopImage: false, dismissAction: nil)
        .environment(ValueRoot.previewWithData)
}
