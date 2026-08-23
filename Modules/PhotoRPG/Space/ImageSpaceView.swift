// @copyright André Trettin

#if os(visionOS)

import RealityKit
import SwiftUI

struct ImageSpaceView: View {
    @Environment(PhotoRootModel.self) private var root

    var body: some View {
        ImagePresentationView(model: root.imagePresentationModel)
            .ornament(
                visibility: root.imagePresentationModel.spatial3DImageState == .generating
                    ? .hidden : .visible,
                attachmentAnchor: .scene(.bottomFront),
                ornament: {
                    OrnamentsView(model: root.imagePresentationModel)
                }
            )
    }
}

#Preview(traits: .mockData) {
    ImageSpaceView()
}

#endif
