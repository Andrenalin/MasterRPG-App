// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import SwiftUI

struct AdventureExtractToolBarButton: View {
    let model: AdventureModel

    @Environment(\.navigator) private var navigator

    var body: some View {
        Button {
            navigator.navigate(to: AdventureDetailRoute.adventureExtraction(model.id), method: .managedSheet)
        } label: {
            Label {
                Text("Extract Information", bundle: .module)
            } icon: {
                Image(systemName: NetworkModules.generator.icon)
            }
        }
        .disabled(model.entries.isEmpty)
    }
}

#Preview(traits: .mockData) {
    AdventureExtractToolBarButton(model: .preview)
}
#endif
