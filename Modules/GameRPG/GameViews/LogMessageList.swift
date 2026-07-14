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
            if !row.sharePlayTransport.isEmpty {
                LogMessageTransportView(transport: row.sharePlayTransport)
            }
            LogMessagePlayersView(statuses: row.playerStatuses, fallback: row.playerNames)
        }
        .foregroundStyle(.primary)
        .listRowBackground(row.deliveryState.rowBackground)
    }
}

private struct LogMessageTransportView: View {
    let transport: SharePlayTransportLog

    var body: some View {
        HStack(spacing: 4) {
            Text("Message:", bundle: .module)
            if let journal = transport.journal {
                Text("Journal", bundle: .module)
                JournalTransportStateImage(state: journal.state)
                Text(Int64(journal.byteCount), format: .byteCount(style: .file))
            }
            if transport.journal != nil, transport.chunked != nil {
                Text("/")
            }
            if let chunked = transport.chunked {
                Text("Chunked \(chunked.count)", bundle: .module)
                Text(Int64(chunked.byteCount), format: .byteCount(style: .file))
            }
        }
        .font(.caption)
        .lineLimit(1)
    }
}

private struct JournalTransportStateImage: View {
    let state: SharePlayJournalTransportState

    var body: some View {
        switch state {
        case .pending:
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Adding to journal", bundle: .module))
        case .succeeded:
            Image(systemName: "checkmark")
                .foregroundStyle(.tint)
                .accessibilityLabel(Text("Added to journal", bundle: .module))
        case .failed:
            Image(systemName: "xmark")
                .foregroundStyle(.red)
                .accessibilityLabel(Text("Failed to add to journal", bundle: .module))
        }
    }
}

private struct LogMessagePlayersView: View {
    let attributedNames: AttributedString

    init(statuses: [LogMessagePlayerStatus], fallback: String) {
        guard !statuses.isEmpty else {
            var fallbackName = AttributedString(fallback)
            fallbackName.foregroundColor = .secondary
            attributedNames = fallbackName
            return
        }

        attributedNames = statuses.enumerated().reduce(into: AttributedString()) { line, entry in
            let (index, status) = entry
            if index > 0 {
                line += AttributedString(", ")
            }

            var name = AttributedString(status.name)
            if status.received {
                name.font = .caption.bold()
            } else {
                name.foregroundColor = .secondary
            }
            line += name
        }
    }

    var body: some View {
        Text(attributedNames)
            .font(.caption)
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
