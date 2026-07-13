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

struct OrnamentsView: View {
    let model: ImagePresentationModel

    var body: some View {
        VStack {
            HStack {
                Button {
                    guard var ipc = model.contentEntity.components[ImagePresentationComponent.self] else {
                        print("Unable to find ImagePresentationComponent.")
                        return
                    }
                    switch ipc.viewingMode {
                    case .mono:
                        switch model.spatial3DImageState {
                        case .generated:
                            ipc.desiredViewingMode = .spatial3D
                            model.contentEntity.components.set(ipc)
                        case .notGenerated:
                            Task {
                                do {
                                    try await model.generateSpatial3DImage()
                                } catch {
                                    print("Spatial3DImage generation failed: \(error.localizedDescription)")
                                    model.spatial3DImageState = .notGenerated
                                }
                            }
                        case .generating:
                            print("Spatial 3D Image is still generating...")
                            return
                        }
                    case .spatial3D:
                        ipc.desiredViewingMode = .mono
                        model.contentEntity.components.set(ipc)
                    default:
                        print("Unhandled viewing mode: \(ipc.viewingMode)")

                    }
                } label: {
                    switch model.contentEntity.observable.components[ImagePresentationComponent.self]?.viewingMode {
                    case .mono:
                        Text(model.spatial3DImageState == .generated ? "Show as 3D" : "Convert to 3D")
                    case .spatial3D:
                        Text("Show as 2D", bundle: .module)
                    default:
                        Text("")
                    }
                }
            }.padding()
        }
        .glassBackgroundEffect()
    }
}

#Preview {
    OrnamentsView(model: ImagePresentationModel())
}

#endif
