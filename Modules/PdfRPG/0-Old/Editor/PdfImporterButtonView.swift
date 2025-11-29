// @copyright André Trettin

import CoreRPG
import SwiftUI

struct PdfImporterButtonView: View {
    @Binding var showImporter: Bool

    var body: some View {
        ImageOverlayButton(icon: "folder\(showImporter ? ".fill" : "")") { showImporter.toggle() }
            .contentTransition(.symbolEffect(.replace.wholeSymbol))    }
}

struct PdfImporterButtonView_Previews: PreviewProvider {
    struct ContainerView: View {
        @State var show: Bool

        var body: some View {
            Color
                .teal
                .frame(width: 256, height: 256)
                .overlay(PdfImporterButtonView(showImporter: $show), alignment: .bottom)
        }
    }

    static var previews: some View {
        Group {
            ContainerView(show: true)
                .preferredColorScheme(.dark)
        }
        .previewLayout(.sizeThatFits)
    }
}
