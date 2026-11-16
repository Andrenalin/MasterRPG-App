// @copyright André Trettin

import SwiftUI

/// Shown where a PDF would appear on Apple TV, which has no PDF viewer (PDFKit is not available
/// there). Without it a revealed PDF left a blank screen with no explanation. Mirrors
/// `SpaceUnsupportedView`.
struct PdfUnsupportedView: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("PDFs Are Not Shown on Apple TV", bundle: .module)
            } icon: {
                Image(systemName: "doc.richtext")
            }
        } description: {
            Text("The Game Master revealed a PDF. Open it on an iPhone, iPad, Mac or Apple Vision Pro.", bundle: .module)
        }
    }
}

#Preview {
    PdfUnsupportedView()
}
