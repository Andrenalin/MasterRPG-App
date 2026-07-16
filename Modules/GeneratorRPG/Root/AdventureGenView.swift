// @copyright André Trettin

import CoreRPG
import FoundationModels
import SwiftUI

struct AdventureGenView: View {
    let adventure: AdventureGenModel.PartiallyGenerated

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading) {
                if let title = adventure.name {
                    Text("Adventure: \(title)", bundle: .module)
                        .contentTransition(.opacity)
                        .font(.largeTitle)
                        .bold()
                }
                if let description = adventure.description {
                    Text(verbatim: description)
                        .contentTransition(.opacity)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top) {
                Image(systemName: "sparkles")
                    .accessibilityHidden(true)
                if let tags = adventure.tags {
                    TagItemRow(tags: tags)
                        .contentTransition(.opacity)
                }
            }
            if let scenarios = adventure.entries {
                ForEach(scenarios, id: \.id) { scenario in
                    ScenarioGenView(scenario: scenario)
                        .padding(.leading)
                        .background(.tint.opacity(0.3))
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut, value: adventure)
    }
}

extension AdventureGenView {
    init() {
        self.init(
            adventure: try! AdventureGenModel.PartiallyGenerated(
                GeneratedContent(
                    json: #"{"name":"The Sealed Gate","description":"Find a way into the old kingdom.","tags":["quest"],"entries":[]}"#
                )
            )
        )
    }
}

#Preview {
    AdventureGenView()
}
