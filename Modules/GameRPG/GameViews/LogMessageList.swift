// @copyright André Trettin

import CoreRPG
import SwiftUI
 
struct LogMessageList: View {
    let logController: LogGameController
    
    @State private var showAttachments = true
    
    var body: some View {
        @Bindable var gameModel = logController.gameModel
        VStack {
            SendControlView(controls: $gameModel.gameControl.controls)
                .padding()
            
            List {
                SharingOptionsSection(features: $gameModel.gameControl.features)
                AttachmentSection(logController: logController, isExpanded: $showAttachments)
                LogRowsSection(logController: logController)
            }
#if os(tvOS)
            .listStyle(.grouped)
#else
            .listStyle(.inset)
#endif
        }
    }
}

private struct SharingOptionsSection: View {
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
            Text("Player Sharing Optionen", bundle: .module)
        }
    }
}

private struct AttachmentSection: View {
    let logController: LogGameController
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroupTV(isExpanded: $isExpanded) {
            ForEach(logController.attachments) { attachment in
                Text("**\(attachment.id)**: \(attachment.itemId)", bundle: .module)
            }
        } label: {
            Text("Attachments in Shareplay", bundle: .module)
        }
    }
}

private struct LogRowsSection: View {
    let logController: LogGameController

    var body: some View {
        Section {
            ForEach(logController.logRows) { row in
                LogMessageRow(row: row)
                    .equatable()
            }
        } header: {
            Text("Message Logs", bundle: .module)
        }
    }
}

private struct LogMessageRow: View, Equatable {
    let row: LogMessageRowModel

    var body: some View {
        VStack(alignment: .leading) {
            Text(row.title)
                .lineLimit(1)
                .font(.caption)
            Text(row.playerNames)
        }
        .foregroundStyle(.black)
        .listRowBackground(row.deliveryState.rowBackground)
    }
}

private extension LogMessageDeliveryState {
    var rowBackground: Color {
        switch self {
        case .notTracked:
            return .blue
        case .missingPlayers:
            return .red.opacity(0.7)
        case .partialPlayers:
            return .yellow
        case .allPlayers:
            return .green
        }
    }
}

#Preview {
    LogMessageList(logController: .preview)
        .environment(\.locale, .init(identifier: "de"))
}

#Preview {
    @Previewable @Bindable var gameModel = LogGameController.preview.gameModel
    SharingOptionsSection(features: $gameModel.gameControl.features)
}

#Preview {
    @Previewable var controller = LogGameController.preview
    @Previewable @State var isExpanded = true
    AttachmentSection(logController: controller, isExpanded: $isExpanded)
}

#Preview {
    LogRowsSection(logController: .preview)
}

#Preview {
    LogMessageRow(
        row: LogMessageRowModel(
            id: 1,
            title: "Map shared",
            playerNames: "Ari, Bea",
            deliveryState: .allPlayers
        )
    )
}
