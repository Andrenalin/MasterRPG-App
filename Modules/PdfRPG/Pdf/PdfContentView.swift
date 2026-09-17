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
                PdfContentViewThumbnailsView(searchModel: searchModel, horizontal: horizontal)
            }
            VStack(spacing: 0) {
                if let pdfDoc = searchModel.pdfDoc {
                    PdfWrapperView(showing: pdfDoc, entry: entry, horizontal: horizontal, searchModel: searchModel)
                } else if searchModel.pdfUnavailable {
                    PdfUnavailableView()
                } else {
                    PdfLoadingView()
                }
                
                if showThumbnail && horizontal {
                    PdfContentViewThumbnailsView(searchModel: searchModel, horizontal: horizontal)
                }
            }
            .task {
                for await notification in NotificationCenter.default.notifications(named: .PDFViewSelectionChanged) {
                    let view = notification.object as? PDFView
                    if let selection = view?.currentSelection, let page = selection.pages.first {
                        let content = String(selection.string?.prefix(300) ?? "")
                        let pageNumber = page.label ?? "-"
                        let bounds = selection.bounds(for: page)
                        searchModel.selectedEntry = root.editController.createBookmark(content: content, page: pageNumber, bounds: bounds)
                    } else {
                        searchModel.selectedEntry = nil
                    }
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
                .moduleForegroundStyle(root.config.module)
#else
                .moduleTint(root.config.module)
#endif
            }
        }
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct PdfContentViewThumbnailsView: View {
    let searchModel: PdfSearchModel
    let horizontal: Bool

    private var horizontalThumbnailSize: CGSize {
        CGSize(width: 54, height: 75)
    }

    private var verticalThumbnailSize: CGSize {
        CGSize(width: 71, height: 100)
    }

    @ViewBuilder
    var body: some View {
        if let pdfView = searchModel.pdfView, let pdfDoc = searchModel.pdfDoc {
            // Both the thumbnail size and the scroll axis/frame need to
            // follow `horizontal` — a horizontal filmstrip scrolls along
            // its width (which grows with page count), a vertical list
            // along its height. See CODE_AUDIT §5.7.
            let thumbnailSize = horizontal ? horizontalThumbnailSize : verticalThumbnailSize
            ScrollView(horizontal ? .horizontal : .vertical) {
                ThumbnailPdfView(pdfView: pdfView, horizontal: horizontal, thumbnailSize: thumbnailSize)
                    .frame(
                        width: horizontal ? CGFloat(pdfDoc.pageCount + 1) * thumbnailSize.width : thumbnailSize.width + 20,
                        height: horizontal ? thumbnailSize.height + 20 : CGFloat(pdfDoc.pageCount + 1) * thumbnailSize.height
                    )
            }
            .background(.tertiary)
            .border(.primary)
            .padding(.vertical, 64)
        }
    }
}

#Preview {
    @Previewable @State var searchModel: PdfSearchModel = PdfSearchModel(pdfDoc: {
        guard let url = PreviewAssetFixture.url(.pdf) else { return PDFDocument() }
        return PDFDocument(url: url) ?? PDFDocument()
    }())
    
    PdfContentView(searchModel: searchModel, horizontal: false, entry: nil)
}

#endif
