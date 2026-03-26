// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import GeneratorRPG
import SwiftUI

#if canImport(PDFKit)
import PDFKit
#endif
#endif

struct DetailListView: View {
    init(root: PdfRootModel, model: PdfModel) {
        self.root = root
        self.model = model
        let listController = root.folderListController.copy(parentModel: model) as! FolderListController
        self._detailFolderListController = State(wrappedValue: listController)
    }
    
    let root: PdfRootModel
    let model: PdfModel
    
    @Environment(\.navigator) private var navigator
    
    @State private var detailFolderListController: FolderListController
    @State private var openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.pdf.viewerWindowId, route: { DetailRoute.viewer($0, nil) })
    @State private var showExtractionSheet = false
    @State private var extractedContent: PdfExtractedContent?
    
    @State private var pdfDocument: PDFDocument?
    
    var body: some View {
        content(listController: detailFolderListController)
            .onChange(of: detailFolderListController.listModel.subFolderRoute) {
                guard let subItemId = detailFolderListController.listModel.subFolderRoute else { return }
                navigator.navigate(to: PdfDetailRoute.folder(subItemId), method: .push)
                detailFolderListController.listModel.subFolderRoute = nil
            }
            .onAppear {
                root.editController.setCurrentItem(to: ItemRowTreeModel(itemId: model.id, typeId: root.config.module))
            }
    }
    
    func content(listController: any FolderListControllable) -> some View {
        ItemDetailRootView(detailListController: listController, selectedModel: model, editorAsBackground: false) {
        } editor: {
            fileAndPlayerView(model: model)
            
            SheetRootEditorView(root: root.rootController, linkControllable: root.linkControllable, model: model, module: root.config.module, headerTitle: String(localized: "Bookmarks", bundle: .module).localizedString, linkTypes: LinkPdfModuleTransferable.self)
        } entryEditor: {
            EntryEditorView(editController: root.editController, model: model, linkTypes: LinkPdfModuleTransferable.self)
        }
        .overlay {
            if openFileWindowModel.showItem {
                root.viewController.viewer(root: root, itemId: openFileWindowModel.itemId, entryId: nil, configuration: ViewerConfiguration(closeButton: true), withoutBookmark: false) {
                    openFileWindowModel.showItem = false
                }
            }
        }
        .environment(openFileWindowModel)
        .environment(root.folderListController.cacheListItemModel)
        .environment(root.listDisplayModel)
        .environment(root.searchModel)
        .environment(root.rootController)
        .tint(root.configurable.module.tint)
        .accentColor(root.configurable.module.tint)
    }
    
    func fileAndPlayerView(model: PdfModel) -> some View {
        VStack(spacing: 12) {
            HStack {
                HStack {
                    FileImporterView(editControllable: root.editController, fileTypes: root.editController.fileUrlDataController?.fileTypes ?? [], itemId: model.id)
                    
                    Text(model.url?.path(percentEncoded: false) ?? "No file is set")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                }
                .opacity(model.specialCategory ? 0 : 1)
            }
            
            // PDF AI Extraction Button
            if model.url != nil, !model.specialCategory {
                Button {
                    Task {
                        pdfDocument = await root.itemController.pdfDocument(for: model.id)
                        showExtractionSheet = true
                    }
                } label: {
                    Label("Extract PDF Information with AI", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .opacity(model.specialCategory ? 0 : 1)
            }
        }
        .padding()
        .sheet(isPresented: $showExtractionSheet) {
            extractionSheet(for: model)
        }
        .sheet(item: $extractedContent) { content in
            NavigationStack {
                ExtractedPdfContentView(content: content)
                    .navigationTitle("Extracted Information")
#if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
#endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                extractedContent = nil
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Apply") {
                                applyExtractedContent(content, to: model)
                                extractedContent = nil
                            }
                        }
                    }
            }
        }
    }
    
    @ViewBuilder
    private func extractionSheet(for model: PdfModel) -> some View {
        NavigationStack {
            Group {
                if let pdfDocument {
                    PdfContentExtractionView(pdfDocument: pdfDocument) { content in
                        showExtractionSheet = false
                        extractedContent = content
                    }
                } else {
                    ContentUnavailableView(
                        "PDF Not Available",
                        systemImage: "doc.questionmark",
                        description: Text("The PDF file could not be loaded.")
                    )
                }
            }
            .navigationTitle("AI PDF Analysis")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        showExtractionSheet = false
                    }
                }
            }
        }
    }
    
    private func applyExtractedContent(_ content: PdfExtractedContent, to model: PdfModel) {
        // Apply the extracted content to the model
        model.applyExtractedContent(content, updateExisting: false)
    }
    
}

#Preview(traits: .mockData) {
    @Previewable @Environment(PdfRootModel.self) var root
    
    ManagedNavigationStack {
        DetailListView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? PdfRootModel.previewSpaceId))
            .preferredColorScheme(.dark)
    }
}
