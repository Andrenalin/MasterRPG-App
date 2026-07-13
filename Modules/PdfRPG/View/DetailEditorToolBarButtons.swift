// @copyright André Trettin

import CoreRPG
import SwiftUI

#if !os(tvOS)

    #Preview(traits: .mockData) {
        @Previewable @Environment(PdfRootModel.self) var root
        ExtractToolBarButton(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
    }

struct ExtractToolBarButton: View {
    let root: PdfRootModel
    let model: PdfModel
    
    @Environment(\.navigator) private var navigator
    
    var body: some View {
        Button {
            navigator.navigate(to: PdfDetailRoute.pdfExtraction(model.id), method: .managedSheet)
        } label: {
            Label {
                Text("Extract Information", bundle: .module)
            } icon: {
                Image(systemName: NetworkModules.generator.icon)
            }
        }
        .disabled(root.openFileWindowModel.showItem)
    }
}

#endif
