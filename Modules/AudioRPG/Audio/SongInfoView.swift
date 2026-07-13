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
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            Text(artist)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
