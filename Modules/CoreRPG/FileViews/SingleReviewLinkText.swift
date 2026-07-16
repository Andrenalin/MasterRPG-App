// @copyright André Trettin

import SwiftUI

/// Review text can contain RPG links; render them read-only without toggling.
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

#Preview { SingleReviewLinkText(text: "Visit [the shrine](RPG://ADVENTURE/preview).") }
