// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import SwiftUI

struct AdventureExtractToolBarButton: View {
    let model: AdventureModel


    var body: some View {
        ExtractInformationToolBarButton(route: AdventureDetailRoute.adventureExtraction(model.id), isDisabled: model.entries.isEmpty)
    }
}

#Preview(traits: .mockData) {
    AdventureExtractToolBarButton(model: .preview)
}
#endif
