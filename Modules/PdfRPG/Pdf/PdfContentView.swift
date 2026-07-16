// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import PDFKit
import SwiftUI

struct PdfContentView: View {
    let searchModel: PdfSearchModel
    let horizontal: Bool
    let entry: PdfEntryModel?
    
    @Environment(PdfRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showThumbnail = false
    
    var body: some View {
        HStack(spacing: 0) {
            if showThumbnail && !horizontal {
                thumbnails
            }
            VStack(spacing: 0) {
                if let pdfDoc = searchModel.pdfDoc {
                    PdfWrapperView(showing: pdfDoc, entry: entry, horizontal: horizontal, searchModel: searchModel)
                } else {
                    VStack {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(1.5)
                            .tint(Color.accentColor)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                
                if showThumbnail && horizontal {
                    thumbnails
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .PDFViewSelectionChanged)) { notification in
                let view = notification.object as? PDFView
                if let selection = view?.currentSelection, let page = selection.pages.first {
                    let content = String(selection.string?.prefix(300) ?? "")
                    let pageNumber = page.label ?? "-"
                    let bounds = selection.bounds(for: page)
                    searchModel.selectedEntry = root.editController.createBookmark(itemId: UUID(), content: content, page: pageNumber, bounds: bounds)
                } else {
                    searchModel.selectedEntry = nil
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(reduceMotion ? nil : .default) {
                        showThumbnail.toggle()
                    }
                } label: {
                    Label {
                        if showThumbnail {
                            Text("Hide thumbnails", bundle: .module)
                        } else {
                            Text("Show thumbnails", bundle: .module)
                        }
                    } icon: {
                        Image(systemName: showThumbnail ? "rectangle.stack" : "rectangle.stack.fill")
                            .contentTransition(.symbolEffect(.automatic))
                    }
                    .labelStyle(.iconOnly)
                }
#if os(macOS)
                .foregroundStyle(root.config.module.tint)
#else
                .tint(root.config.module.tint)
#endif
            }
        }
    }
    
    private var horizontalThumnailSize: CGSize {
        CGSize(width: 54, height: 75)
    }
    
    private var verticalThumnailSize: CGSize {
        CGSize(width: 71, height: 100)
    }
    
    @ViewBuilder
    private var thumbnails: some View {
        if let pdfView = searchModel.pdfView, let pdfDoc = searchModel.pdfDoc {
            ScrollView(.vertical) {
                ThumbnailPdfView(pdfView: pdfView, horizontal: horizontal, thumbnailSize: verticalThumnailSize)
                    .frame(width: verticalThumnailSize.width + 20, height: CGFloat(pdfDoc.pageCount + 1) * (verticalThumnailSize.height))
            }
            .background(.tertiary)
            .border(.primary)
            .padding(.vertical, 64)
        }
    }
}


#Preview {
    @Previewable @State var searchModel: PdfSearchModel = PdfSearchModel(pdfDoc: {
        if let asset = NSDataAsset(name: "PdfTest") {
            let data = asset.data
            return PDFDocument(data: data) ??
            PDFDocument()
        }
        return nil
    }())
    
    PdfContentView(searchModel: searchModel, horizontal: false, entry: nil)
}

#endif
