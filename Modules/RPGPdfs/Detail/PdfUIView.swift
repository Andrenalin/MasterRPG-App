// @copyright André Trettin

#if !os(tvOS)
import AndrenalinKit
@preconcurrency import PDFKit
import QuickLook
import SwiftUI

#if os(macOS)
import AppKit
import QuickLookUI
#endif

#if os(macOS)
typealias CustomViewRepresentable = NSViewRepresentable
#else
typealias CustomViewRepresentable = UIViewRepresentable
#endif

struct PDFUIView: View {
    let searchModel: PdfSearchModel
    let horizontal: Bool
    let entry: PdfEntryModel?
    
    @State private var showThumbnail = false
    
    var body: some View {
        //let _ = Self._printChanges()
        
        HStack(spacing: 0) {
            if showThumbnail && !horizontal {
                thumbnails
            }
            VStack(spacing: 0) {
                if let pdfDoc = searchModel.pdfDoc {
                    PDFWrapperView(showing: pdfDoc, entry: entry, horizontal: horizontal, searchModel: searchModel)
                } else {
                    VStack {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.large)
                            .tint(.teal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                
                if showThumbnail && horizontal {
                    thumbnails
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.PDFViewSelectionChanged)) { notification in
                let view = notification.object as? PDFView
                if let selection = view?.currentSelection, let page = selection.pages.first {
                    let content = String(selection.string?.prefix(300) ?? "")
                    let pageNumber = page.label ?? "-"
                    let bounds = selection.bounds(for: page)
                    searchModel.selectedEntry = PdfEntryModel.createEntry(content: content, page: pageNumber, bounds: bounds)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            Button {
                withAnimation { showThumbnail.toggle() }
            } label: {
                Image(systemName: showThumbnail ? "rectangle.stack" : "rectangle.stack.fill")
                    .contentTransition(.symbolEffect(.automatic))
            }
            .buttonStyle(.borderedProminent)
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
                ThumbnailPDFView(pdfView: pdfView, horizontal: horizontal, thumbnailSize: verticalThumnailSize)
                    .frame(width: verticalThumnailSize.width + 20, height: CGFloat(pdfDoc.pageCount + 1) * (verticalThumnailSize.height))
            }
            .background(.tertiary)
            .border(.primary)
        }
    }
}

struct PDFWrapperView: CustomViewRepresentable {
    let pdfDocument: PDFDocument?
    let horizontal: Bool
    let entry: PdfEntryModel?
    let searchModel: PdfSearchModel
    
    init(url: URL, entry: PdfEntryModel?, horizontal: Bool, searchModel: PdfSearchModel) {
        pdfDocument = PDFDocument(url: url)
        self.entry = entry
        self.horizontal = horizontal
        self.searchModel = searchModel
    }
    
    init(showing pdfDoc: PDFDocument, entry: PdfEntryModel?, horizontal: Bool, searchModel: PdfSearchModel) {
        pdfDocument = pdfDoc
        self.entry = entry
        self.horizontal = horizontal
        self.searchModel = searchModel
    }
    
#if os(macOS)
    func makeNSView(context _: Context) -> PDFView {
        makeView()
    }
#else
    func makeUIView(context _: Context) -> PDFView {
        makeView()
    }
#endif

    @MainActor
    func makeView() -> PDFView {
        let pdfView = PDFView()
        
        pdfView.document = pdfDocument
        pdfView.autoScales = false
        pdfView.autoresizesSubviews = true
        pdfView.displayDirection = horizontal ? .horizontal : .vertical
        pdfView.minScaleFactor = 0.25
        pdfView.maxScaleFactor = 5.0
        pdfView.displayMode = .singlePageContinuous
#if os(iOS) || os(visionOS)
        pdfView.isFindInteractionEnabled = true
#endif
        
        if let entry, let pageNo = Int(entry.pageLabel) {
            if let page = pdfDocument?.page(at: pageNo - 1), let selection = page.selection(for: entry.bounds) {
                pdfView.go(to: page)
                selection.color = AKColor.yellow
                pdfView.highlightedSelections = [selection]
            }
        }
        Task { @MainActor in
            searchModel.pdfView = pdfView
        }
        return pdfView
    }
    
#if os(macOS)
    func updateNSView(_ pdfView: PDFView, context: Context) {
        updateView(pdfView, context: context)
    }
#else
    func updateUIView(_ pdfView: PDFView, context: Context) {
        updateView(pdfView, context: context)
    }
#endif

    @MainActor
    func updateView(_ pdfView: PDFView, context: Context) {
        pdfView.document?.delegate = context.coordinator
        pdfView.delegate = context.coordinator
        
        if !searchModel.pdfSearching && !searchModel.searchText.isEmpty {
            let searchText = searchModel.searchText
            Task { @MainActor in
                searchModel.pdfSearching = true
                searchModel.isSearching = true
                let searchTask = Task.detached {
                    await pdfView.document?.findString(searchText, withOptions: .caseInsensitive)
                }
                
                let matches = await searchTask.value
                matches?.forEach { match in
                    match.color = AKColor.yellow
                }
                if let match = matches?.first {
                    pdfView.go(to: match)
                }
                pdfView.highlightedSelections = matches
                Task { @MainActor in
                    if let matches {
                        searchModel.matches = matches
                        searchModel.currentIndex = 0
                        searchModel.setSearchMatch = { matches, index in
                            let selection = matches[index]
                            pdfView.go(to: selection)
                            selection.color = AKColor.clear
                            var updatedMatches = matches
                            updatedMatches[index] = selection
                            pdfView.highlightedSelections = updatedMatches
                            Task {
                                try await Task.sleep(for: .seconds(0.25))
                                selection.color = AKColor.yellow
                                updatedMatches[index] = selection
                                pdfView.highlightedSelections = updatedMatches
                            }
                        }
                    }
                    searchModel.isSearching = false
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }
    
    final class Coordinator: NSObject, PDFViewDelegate, PDFDocumentDelegate {
        let parent: PDFWrapperView
        
        init(parent: PDFWrapperView) {
            self.parent = parent
        }
        
        @objc func handlePageChange(notification: Notification) {
            //parent.pageLabel(pdfView: parent.pdfView, viewSize: parent.viewSize)
        }
    }
}


struct ThumbnailPDFView: CustomViewRepresentable {
    let pdfView: PDFView?
    let horizontal: Bool
    let thumbnailSize: CGSize
    
#if os(macOS)
    func makeNSView(context _: Context) -> PDFThumbnailView {
        makeView()
    }
#else
    func makeUIView(context _: Context) -> PDFThumbnailView {
        makeView()
    }
#endif

    @MainActor
    func makeView() -> PDFThumbnailView {
        let view = PDFThumbnailView()
        view.thumbnailSize = thumbnailSize
#if os(iOS) || os(visionOS)
        view.layoutMode = horizontal ? .horizontal : .vertical
        view.backgroundColor = .systemGray
        view.contentInset = UIEdgeInsets(top: 10, left: 5, bottom: 10, right: 5)
#else
        view.backgroundColor = NSColor.underPageBackgroundColor
#endif
        view.pdfView = pdfView
        return view
    }
    
#if os(macOS)
    func updateNSView(_ pdfView: PDFThumbnailView, context: Context) {
        updateView(pdfView, context: context)
    }
#else
    func updateUIView(_ pdfView: PDFThumbnailView, context: Context) {
        updateView(pdfView, context: context)
    }
#endif
    
    func updateView(_ pdfView: PDFThumbnailView, context: Context) {
    }
}

#if os(macOS)
struct PreviewControllerWrapperView: NSViewRepresentable {
    let fileStore: FileUrlDataController
    let pathUrl: NSURL
    
    func makeNSView(context _: Context) -> QLPreviewView {
        let preview = QLPreviewView(frame: .zero, style: .compact)
        preview?.autostarts = true
        return preview ?? QLPreviewView()
    }
    
    func updateNSView(_: QLPreviewView, context: Context) {
        let panel = QLPreviewPanel.shared()
        panel?.center()
        panel?.dataSource = context.coordinator
        panel?.makeKeyAndOrderFront(nil)
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }
    
    final class Coordinator: QLPreviewPanelDataSource {
        let parent: PreviewControllerWrapperView
        
        init(parent: PreviewControllerWrapperView) {
            self.parent = parent
        }
        
        func numberOfPreviewItems(in _: QLPreviewPanel) -> Int {
            return 1
        }
        
        func previewPanel(_: QLPreviewPanel!, previewItemAt _: Int) -> QLPreviewItem! {
            parent.pathUrl.startAccessingSecurityScopedResource()
            defer { parent.pathUrl.stopAccessingSecurityScopedResource() }
            
            return parent.pathUrl
        }
    }
}

#else

struct PreviewControllerWrapperView: UIViewControllerRepresentable {
    let fileStore: FileUrlDataController
    let pathUrl: NSURL
    
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.isEditing = false
        return controller
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }
    
    func updateUIViewController(_ controller: QLPreviewController, context _: Context) {
        controller.refreshCurrentPreviewItem()
    }
    
    final class Coordinator: QLPreviewControllerDataSource {
        let parent: PreviewControllerWrapperView
        
        init(parent: PreviewControllerWrapperView) {
            self.parent = parent
        }
        
        func numberOfPreviewItems(in _: QLPreviewController) -> Int {
            return 1
        }
        
        func previewController(_: QLPreviewController, previewItemAt _: Int) -> QLPreviewItem {
            parent.pathUrl.startAccessingSecurityScopedResource()
            defer { parent.pathUrl.stopAccessingSecurityScopedResource() }
            return parent.pathUrl
        }
    }
}

#endif

struct PDFUIView_Preview: PreviewProvider {
    static var pdfDoc: PDFDocument {
        if let asset = NSDataAsset(name: "Wurzel") {
            let data = asset.data
            return PDFDocument(data: data) ??
            PDFDocument()
        }
        fatalError("Cannot load pdf")
    }
    
    static var data: Data {
        if let asset = NSDataAsset(name: "Wurzel") {
            let data = asset.data
            return data
        }
        fatalError("Cannot load pdf")
    }
    
    static var url: URL {
        if let url = Bundle.main.url(forResource: "Geheimnis", withExtension: "pdf") {
            return url
        }
        fatalError("Cannot load pdf")
    }
    
    static var previews: some View {
        Group {
            PDFUIView(searchModel: PdfSearchModel(), horizontal: false, entry: nil)
            //PreviewControllerWrapperView(url: url)
        }
    }
}

#endif
