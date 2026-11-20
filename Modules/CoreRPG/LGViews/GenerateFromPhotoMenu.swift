// @copyright André Trettin

import SwiftUI

/// The "Generate" entry of a photo's context menu, in the editor list and in the link/game list
/// alike: a submenu of what can be made from the photo. The host provides what is offered and
/// what it does through `generateFromPhotoAction`.
struct GenerateFromPhotoMenu: View {
    let photoId: UUID

    @Environment(\.generateFromPhotoAction) private var generateFromPhotoAction

    var body: some View {
        if generateFromPhotoAction.kinds == [.map] {
            // A game offers only the map: no submenu for one entry.
            GenerateFromPhotoButton(kind: .map, photoId: photoId)
        } else if generateFromPhotoAction.isEnabled {
            Menu {
                GenerateFromPhotoButton(kind: .map, photoId: photoId)
                GenerateFromPhotoButton(kind: .character, photoId: photoId)
                GenerateFromPhotoButton(kind: .characterClone, photoId: photoId)
            } label: {
                Label {
                    Text("Generate", bundle: .module)
                } icon: {
                    Image(systemName: "gear")
                }
            }
        }
    }
}

private struct GenerateFromPhotoButton: View {
    let kind: PhotoGenerationKind
    let photoId: UUID

    @Environment(\.generateFromPhotoAction) private var generateFromPhotoAction

    var body: some View {
        if generateFromPhotoAction.supports(kind) {
            Button {
                generateFromPhotoAction(kind, photoId: photoId)
            } label: {
                Label {
                    switch kind {
                    case .map: Text("Generate Map", bundle: .module)
                    case .character: Text("Generate New Character", bundle: .module)
                    case .characterClone: Text("Generate Clone Character…", bundle: .module)
                    }
                } icon: {
                    switch kind {
                    case .map: Image(systemName: "map")
                    case .character: Image(systemName: "person.crop.circle.badge.plus")
                    case .characterClone: Image(systemName: "person.2.circle")
                    }
                }
            }
        }
    }
}
