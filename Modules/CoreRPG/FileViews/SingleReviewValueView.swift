// @copyright André Trettin

import SwiftUI

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

#Preview { SingleReviewValueView(kind: .tags, value: "dungeon, mystery, undead") }
