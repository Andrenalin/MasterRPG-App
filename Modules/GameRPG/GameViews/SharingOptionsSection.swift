// @copyright André Trettin

import CoreRPG
import SwiftUI

struct SharingOptionsSection: View {
    @Binding var features: GameFeatureModel

    var body: some View {
        DisclosureGroupTV {
            Toggle(isOn: $features.diceMaster) {
                Label {
                    Text("Share master dice with other players", bundle: .module)
                } icon: {
                    Image(systemName: NetworkModules.dice.icon)
                }
            }
            Toggle(isOn: $features.dicePlayers) {
                Label {
                    Text("Share player dice with other players", bundle: .module)
                } icon: {
                    Image(systemName: NetworkModules.dice.icon)
                }
            }
            Toggle(isOn: $features.audioSharing) {
                Label {
                    Text(NetworkModules.audio.localizedTitle)
                } icon: {
                    Image(systemName: NetworkModules.audio.icon)
                }
            }
            Toggle(isOn: $features.photoSharing) {
                Label {
                    Text(NetworkModules.photo.localizedTitle)
                } icon: {
                    Image(systemName: NetworkModules.photo.icon)
                }
            }
            Toggle(isOn: $features.spaceSharing) {
                Label {
                    Text(NetworkModules.space.localizedTitle)
                } icon: {
                    Image(systemName: NetworkModules.space.icon)
                }
            }
        } label: {
            Text("Player Sharing Options", bundle: .module)
        }
    }
}

#Preview {
    @Previewable @State var features = GameFeatureModel()
    SharingOptionsSection(features: $features)
}
