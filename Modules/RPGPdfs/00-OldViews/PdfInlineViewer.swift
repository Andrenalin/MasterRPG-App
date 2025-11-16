// @copyright André Trettin

import AndrenalinKit
#if !os(tvOS)
import PDFKit
#endif
import SwiftUI

struct PdfInlineViewer: View {
    init(model: PdfModel) {
        self.model = model
    }

    let model: PdfModel

    @Environment(PdfRootModel.self) private var root

    @State private var showThumbnails: Bool = false
    @State private var pdfUrl: NSURL?
    @State private var fileUrl: FileUrl?

    var body: some View {
#if os(tvOS)
        Image(systemName: "doc.on.doc")
#else
        @Bindable var model = model
        Group {
//            if let pdfUrl {
//                PreviewControllerWrapperView(fileStore: root.fileUrlDataController!, pathUrl: pdfUrl)
//                    .frame(height: 450)
//            } else {
                Text("Loading PDF document ...", bundle: .module)
//            }
        }
        .onChange(of: model.fileUrl, initial: true) {
            withAnimation {
                loadPdf()
            }
        }
#endif
    }

    func loadPdf() {
        Task { @MainActor in
            guard let fileUrl = model.fileUrl else { return }
            pdfUrl = await root.fileUrlDataController?.url(for: fileUrl, action: { url -> NSURL? in
                guard let url else { return nil }
                return NSURL(fileURLWithPath: url.path)
            })
        }
    }
}
