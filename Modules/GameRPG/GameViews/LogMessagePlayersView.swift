// @copyright André Trettin

import SwiftUI

struct LogMessagePlayersView: View {
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

#Preview {
    LogMessagePlayersView(
        statuses: [
            .init(id: GamePreviewData.playerID, name: "Aria", received: true),
            .init(id: GamePreviewData.secondPlayerID, name: "Borin", received: false)
        ],
        fallback: "No players"
    )
}
