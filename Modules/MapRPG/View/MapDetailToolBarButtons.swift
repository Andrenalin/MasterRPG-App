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

    @Environment(\.navigator) private var navigator

    var body: some View {
        Button {
            navigator.navigate(to: MapDetailRoute.mapExtraction(model.id), method: .managedSheet)
        } label: {
            Label {
                Text("Extract Information", bundle: .module)
            } icon: {
                Image(systemName: NetworkModules.generator.icon)
            }
        }
        .disabled(model.entries.filter { !$0.isHexGrid }.isEmpty)
    }
}
#endif
