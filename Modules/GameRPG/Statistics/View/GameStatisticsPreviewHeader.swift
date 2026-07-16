// @copyright André Trettin

import SwiftUI

struct GameStatisticsPreviewHeader: View {
    let collectionEnabled: Bool

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Label {
                    Text("Your Adventures, Visualized", bundle: .module)
                } icon: {
                    Image(systemName: "sparkles.rectangle.stack")
                }
                .font(.title2)
                .bold()

                Spacer()

                Text("Example", bundle: .module)
                    .textCase(.uppercase)
                    .font(.caption)
                    .bold()
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(.blue, in: .capsule)
                    .foregroundStyle(.white)
            }

            Text("This sample dashboard shows what MasterRPG can discover from activity during your games. Example data is never saved or reported to Game Center.", bundle: .module)
                .foregroundStyle(.secondary)

            if collectionEnabled {
                Label {
                    Text("Finish a game lasting at least 15 minutes to replace this preview with your own story.", bundle: .module)
                } icon: {
                    Image(systemName: "flag.checkered")
                }
            } else {
                Label {
                    Text("Turn on collection in Customize to build your personal dashboard.", bundle: .module)
                } icon: {
                    Image(systemName: "chart.bar.doc.horizontal")
                }
                .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.blue.opacity(0.12), in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    GameStatisticsPreviewHeader(collectionEnabled: true)
        .padding()
}
