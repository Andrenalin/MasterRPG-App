// @copyright André Trettin

import SwiftUI

struct GameStatisticsEntryLabel: View {
    let sessionCount: Int

    var body: some View {
        HStack {
            Image(systemName: "chart.bar.xaxis")
                .imageScale(.large)

            VStack(alignment: .leading) {
                Text("Game Statistics", bundle: .module)
                    .bold()
                if sessionCount == 0 {
                    Text("Explore an example dashboard", bundle: .module)
                        .font(.caption)
                } else {
                    Text("Recorded games: \(sessionCount)", bundle: .module)
                        .font(.caption)
                }
            }

            Spacer()
            Image(systemName: "chevron.forward")
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    GameStatisticsEntryLabel(sessionCount: 12)
        .padding()
}
