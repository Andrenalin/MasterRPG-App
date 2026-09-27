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
    
    var body: some View {
        ExtractInformationToolBarButton(route: PdfDetailRoute.pdfExtraction(model.id), isDisabled: root.openFileWindowModel.showItem)
    }
}

#endif
