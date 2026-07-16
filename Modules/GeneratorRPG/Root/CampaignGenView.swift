// @copyright André Trettin

import CoreRPG
import FoundationModels
import SwiftUI

struct CampaignGenView: View {
    let campaign: CampaignGenModel.PartiallyGenerated

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading) {
                if let title = campaign.name {
                    Text("Campaign: \(title)", bundle: .module)
                        .contentTransition(.opacity)
                        .font(.largeTitle)
                        .bold()
                }
                if let description = campaign.description {
                    Text(verbatim: description)
                        .contentTransition(.opacity)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top) {
                Image(systemName: "sparkles")
                    .accessibilityHidden(true)
                if let tags = campaign.tags {
                    TagItemRow(tags: tags)
                        .contentTransition(.opacity)
                }
            }
            if let adventures = campaign.entries {
                ForEach(adventures, id: \.id) { adventure in
                    AdventureGenView(adventure: adventure)
                        .padding(.leading)
                        .background(.tint.opacity(0.3))
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut, value: campaign)
    }
}

extension CampaignGenView {
    init() {
        self.init(
            campaign: try! CampaignGenModel.PartiallyGenerated(
                GeneratedContent(
                    json: #"{"name":"Under the Mountain","description":"A lost dwarven realm.","tags":["dwarves","ruins"],"entries":[]}"#
                )
            )
        )
    }
}

#Preview {
    CampaignGenView()
}
