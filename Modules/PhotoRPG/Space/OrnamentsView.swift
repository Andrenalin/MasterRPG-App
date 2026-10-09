// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import RealityKit
import SwiftUI
import os.log

struct OrnamentsView: View {
    let model: ImagePresentationModel

    var body: some View {
        VStack {
            HStack {
                Button {
                    guard var component = model.contentEntity.components[ImagePresentationComponent.self] else {
                        Logger.photoSpace.error("Unable to find ImagePresentationComponent.")
                        return
                    }
                    switch component.viewingMode {
                    case .mono:
                        switch model.spatial3DImageState {
                        case .generated:
                            component.desiredViewingMode = .spatial3D
                            model.contentEntity.components.set(component)
                        case .notGenerated:
                            Task {
                                do {
                                    try await model.generateSpatial3DImage()
                                } catch {
                                    Logger.photoSpace.error("Spatial3DImage generation failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                                    model.spatial3DImageState = .notGenerated
                                }
                            }
                        case .generating:
                            Logger.photoSpace.debug("Spatial 3D Image is still generating...")
                        }
                    case .spatial3D:
                        component.desiredViewingMode = .mono
                        model.contentEntity.components.set(component)
                    default:
                        Logger.photoSpace.error("Unhandled viewing mode: \(String(describing: component.viewingMode), privacy: .public)")
                    }
                } label: {
                    switch model.contentEntity.observable.components[ImagePresentationComponent.self]?.viewingMode {
                    case .mono:
                        if model.spatial3DImageState == .generated {
                            Text("Show as 3D", bundle: .module)
                        } else {
                            Text("Convert to 3D", bundle: .module)
                        }
                    case .spatial3D:
                        Text("Show as 2D", bundle: .module)
                    default:
                        Text(verbatim: "")
                    }
                }
            }
            .padding()
        }
        .glassBackgroundEffect()
    }
}

#Preview {
    OrnamentsView(model: ImagePresentationModel())
}
#endif
