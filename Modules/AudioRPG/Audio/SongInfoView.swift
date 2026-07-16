// @copyright André Trettin

import SwiftUI

#Preview {
    SongInfoView(title: "The Tavern at Midnight", artist: "MasterRPG Orchestra")
        .padding()
}

struct SongInfoView: View {
    let title: String
    let artist: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: title)
                .font(.caption)
                .bold()
                .lineLimit(1)

            Text(verbatim: artist)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
