// @copyright André Trettin

import SwiftUI

struct SingleReviewAlternativeBlock: View {
    let decision: SingleReviewDecision
    var kind: SingleReviewKind = .text
    let value: String?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 5) {
                Label(decision.title, systemImage: decision.systemImage)
                    .font(.caption2)
                    .bold()
                    .foregroundStyle(decision.tint)
                SingleReviewValueView(kind: kind, value: value)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.primary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(decision.tint.opacity(0.08))
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(decision.tint.opacity(0.2), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Choose this version for the property", bundle: .module))
    }
}

// Review text can contain RPG:// markdown links; render them read-only, no toggling.
struct SingleReviewLinkText: View {
    init(text: String) {
        self.text = text
        _model = State(initialValue: LinkHighlightTextModel(linkControllable: nil, text: text))
    }

    let text: String
    @State private var model: LinkHighlightTextModel

    var body: some View {
        LinkHighlightTextView(model: model)
            .onChange(of: text) { _, newText in
                model.reset(text: newText)
            }
    }
}

struct SingleReviewValueView: View {
    let kind: SingleReviewKind
    let value: String?
    var lineLimit: Int? = nil

    var body: some View {
        switch kind {
        case .tags:
            SingleReviewTagValue(tags: value.reviewTags)
        case .text, .sublist:
            SingleReviewLinkText(text: value ?? "—")
                .lineLimit(lineLimit)
        case .picker(options: _), .binary, .link:
            Text(value ?? "—")
                .lineLimit(lineLimit)
        }
    }
}

private struct SingleReviewTagValue: View {
    let tags: [String]

    var body: some View {
        if tags.isEmpty {
            Text("—")
        } else if tags.count > 4 {
            let half = tags.count / 2

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    TagItemRow(tags: Array(tags[..<half]))
                }
                HStack(spacing: 4) {
                    TagItemRow(tags: Array(tags[half...]))
                }
            }
        } else {
            HStack(spacing: 4) {
                TagItemRow(tags: tags)
            }
        }
    }
}

private extension Optional where Wrapped == String {
    var reviewTags: [String] {
        guard let value = self else { return [] }
        return value
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
