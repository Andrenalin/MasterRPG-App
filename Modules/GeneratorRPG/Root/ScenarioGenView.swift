// @copyright André Trettin

import CoreRPG
import FoundationModels
import SwiftUI

struct ScenarioGenView: View {
    let scenario: ScenarioGenModel.PartiallyGenerated

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading) {
                if let title = scenario.name {
                    Text("Scenario: \(title)", bundle: .module)
                        .contentTransition(.opacity)
                        .font(.largeTitle)
                        .bold()
                }
                if let description = scenario.description {
                    Text(verbatim: description)
                        .contentTransition(.opacity)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top) {
                Image(systemName: "sparkles")
                    .accessibilityHidden(true)
                if let tags = scenario.tags {
                    TagItemRow(tags: tags)
                        .contentTransition(.opacity)
                }
            }
            if let entries = scenario.entries {
                ForEach(entries, id: \.id) { entry in
                    EntryGenView(entry: entry)
                        .padding(.leading)
                        .background(.tint.opacity(0.3))
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut, value: scenario)
    }
}

extension ScenarioGenView {
    init() {
        self.init(
            scenario: try! ScenarioGenModel.PartiallyGenerated(
                GeneratedContent(
                    json: #"{"name":"Echoing Hall","description":"Ancient mechanisms awaken.","tags":["encounter"],"entries":[]}"#
                )
            )
        )
    }
}

#Preview {
    ScenarioGenView()
}
