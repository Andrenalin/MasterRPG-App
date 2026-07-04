// @copyright André Trettin

import SwiftUI

struct SingleReviewDecisionHeaderView: View {
    let item: SingleItemImportModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.title2)
                .bold()
            Text(item.description)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SingleReviewDecisionCardsView: View {
    let model: SingleItemImportModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SingleReviewDecisionHeaderView(item: model)

            HStack(spacing: 10) {
                ForEach(SingleReviewDecision.allCases) { decision in
                    Button {
                        model.applyItemDecision(decision)
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: decision.systemImage)
                                .font(.title2)
                            Text(decision.title)
                                .font(.subheadline)
                                .bold()
                            Text(decision.tagline)
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(model.decision == decision ? decision.tint : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(model.decision == decision ? decision.tint.opacity(0.14) : Color.secondary.opacity(0.06))
                        .foregroundStyle(model.decision == decision ? decision.tint : .secondary)
                        .clipShape(.rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(model.decision == decision ? decision.tint : Color.clear, lineWidth: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(decision.title))
                    .accessibilityHint(Text(decision.tagline))
                    .accessibilityAddTraits(model.decision == decision ? .isSelected : [])
                }
            }

            if model.hasPropertyOverrides {
                Label {
                    Text("Some properties have custom overrides", bundle: .module)
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
