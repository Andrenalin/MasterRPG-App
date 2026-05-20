// @copyright André Trettin

import CoreRPG
import SwiftUI

#if !os(tvOS)

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
