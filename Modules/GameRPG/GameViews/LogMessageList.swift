// @copyright André Trettin

import CoreRPG
import SwiftUI
 
struct LogMessageList: View {
    let logController: LogGameController
    
    @State private var showAttachments = true
    
    var body: some View {
        @Bindable var gameModel = logController.gameModel
        VStack {
            SendControlView(controls: $gameModel.gameConfig.controls)
                .padding()
            
            List {
                
                sharingView
                attachmentView
                
                logsView
            }
#if os(tvOS)
            .listStyle(.grouped)
#else
            .listStyle(.inset)
#endif
        }
    }
    
    private func rowColor(message: LogGameModel) -> Color {
        guard message.type == .reveal else { return .blue }
        if logController.maxPlayers > 0 && message.players.isEmpty {
            return .red.opacity(0.7)
        }
        if message.players.count < logController.maxPlayers {
            return .yellow
        }
        return .green
    }
    
    private func playerNames(message: LogGameModel) -> String {
        let players = message.players
        if players.isEmpty {
            return String(localized: "No Players").localizedString
        } else {
            return logController.playerNames(for: message.players)
        }
    }
    
    @ViewBuilder
    private var sharingView: some View {
        @Bindable var gameModel = logController.gameModel
        
        DisclosureGroupTV {
            Toggle(isOn: $gameModel.gameConfig.features.diceMaster) {
                Label {
                    Text("Share master dice with other players", bundle: .module)
                } icon: {
                    Image(systemName: NetworkModules.dice.icon)
                }
            }
            
            Toggle(isOn: $gameModel.gameConfig.features.dicePlayers) {
                Label {
                    Text("Share player dice with other players", bundle: .module)
                } icon: {
                    Image(systemName: NetworkModules.dice.icon)
                }
            }
            
            Toggle(isOn: $gameModel.gameConfig.features.audioSharing) {
                Label {
                    Text(NetworkModules.audio.localizedTitle)
                } icon: {
                    Image(systemName: NetworkModules.audio.icon)
                }
            }
            Toggle(isOn: $gameModel.gameConfig.features.photoSharing) {
                Label {
                    Text(NetworkModules.photo.localizedTitle)
                } icon: {
                    Image(systemName: NetworkModules.photo.icon)
                }
            }
            Toggle(isOn: $gameModel.gameConfig.features.spaceSharing) {
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
    
    private var attachmentView: some View {
        DisclosureGroupTV(isExpanded: $showAttachments) {
            ForEach(logController.attachments) { attachment in
                Text(attachment.id).bold() + Text(": \(attachment.itemId)")
            }
        } label: {
            Text("Attachments in Shareplay", bundle: .module)
        }
    }

    private var logsView: some View {
        Section {
            ForEach(logController.logModels.reversed()) { message in
                VStack(alignment: .leading) {
                    Text("\(message.id): \(message.type.debugDescription) -  \(message.subType.debugDescription) - \(message.module.token) \(logController.name(for: message.module, itemId: message.itemId))")
                        .lineLimit(1)
                        .font(.caption)
                    Text(playerNames(message:message))
                }
                .foregroundStyle(Color.black)
                .listRowBackground(rowColor(message: message))
            }
        } header: {
            Text("Message Logs", bundle: .module)
        }
    }

    private var playerImagesView: some View {
        HStack {
            ForEach(logController.players) {
                if let data = $0.data, let image = AKImage(data: data) {
                    Image(akImage: image)
                        .resizable()
                        .frame(width: 320, height: 256)
                }
                Text($0.name)
            }
        }
    }
}

//#Preview {
//    LogMessageList(logController: .preview)
//        .environment(\.locale, .init(identifier: "de"))
//}
