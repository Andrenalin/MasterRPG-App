// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import SwiftUI

#if !os(tvOS)
#Preview(traits: .mockData) {
    TableExtractToolBarButton(model: .preview)
}
#endif

#if !os(tvOS)
struct TableExtractToolBarButton: View {
    let model: TableModel

    @Environment(\.navigator) private var navigator

    var body: some View {
        Button {
            navigator.navigate(to: TableDetailRoute.tableExtraction(model.id), method: .managedSheet)
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
#endif
