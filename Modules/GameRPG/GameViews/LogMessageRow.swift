// @copyright André Trettin

import CoreRPG
import SwiftUI

struct LogMessageRow: View, Equatable {
    let row: LogMessageRowModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
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

extension LogMessageDeliveryState {
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
    LogMessageRow(
        row: LogMessageRowModel(
            id: 1,
            title: "Map shared",
            playerNames: "Aria, Borin",
            deliveryState: .allPlayers,
            playerStatuses: [
                .init(id: GamePreviewData.playerId, name: "Aria", received: true),
                .init(id: GamePreviewData.secondPlayerId, name: "Borin", received: false)
            ],
            sharePlayTransport: SharePlayTransportLog(
                journal: .init(byteCount: 4_096, state: .succeeded),
                chunked: .init(count: 3, byteCount: 12_288)
            )
        )
    )
}
