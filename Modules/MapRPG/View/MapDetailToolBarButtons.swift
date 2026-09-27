// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif

#if !os(tvOS)
#Preview(traits: .mockData) { MapExtractToolBarButton(model: .preview) }
#endif
import SwiftUI

#if !os(tvOS)
struct MapExtractToolBarButton: View {
    let model: MapModel

    var body: some View {
        ExtractInformationToolBarButton(route: MapDetailRoute.mapExtraction(model.id), isDisabled: model.entries.filter { !$0.isHexGrid }.isEmpty)
    }
}
#endif
