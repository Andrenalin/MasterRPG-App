// @copyright André Trettin

import SwiftUI

struct SheetEntryReviewButton: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let model: SheetEntryReviewModel

    var body: some View {
        Button(
            String(localized: "Versions", bundle: .module),
            systemImage: "square.stack.3d.up",
            action: toggleVersions
        )
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityValue(
            model.isExpanded
                ? Text("Expanded", bundle: .module)
                : Text("Collapsed", bundle: .module)
        )
        .help(Text("Compare entry versions", bundle: .module))
    }

    private func toggleVersions() {
        withAnimation(accessibilityReduceMotion ? nil : .smooth) {
            model.toggleExpanded()
        }
    }
}

#Preview("Entry Review Button") {
    let fixture = SheetEntryReviewPreviewFixture(isExpanded: false)
    SheetEntryReviewButton(model: fixture.reviewModel)
}
