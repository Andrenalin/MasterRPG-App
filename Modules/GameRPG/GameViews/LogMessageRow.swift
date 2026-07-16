// @copyright André Trettin

import SwiftUI

struct LogMessageRow: View, Equatable {
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

#Preview {
    LogMessageRow(
        row: LogMessageRowModel(
            id: 1,
            title: "Map shared",
            playerNames: "Aria, Borin",
            deliveryState: .allPlayers,
            playerStatuses: [
                .init(id: GamePreviewData.playerID, name: "Aria", received: true),
                .init(id: GamePreviewData.secondPlayerID, name: "Borin", received: false)
            ],
            sharePlayTransport: SharePlayTransportLog(
                journal: .init(byteCount: 4_096, state: .succeeded),
                chunked: .init(count: 3, byteCount: 12_288)
            )
        )
    )
}
