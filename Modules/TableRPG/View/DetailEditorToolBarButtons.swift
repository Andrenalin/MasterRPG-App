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


    var body: some View {
        ExtractInformationToolBarButton(route: TableDetailRoute.tableExtraction(model.id), isDisabled: model.entries.isEmpty)
    }
}
#endif
