// @copyright André Trettin

import CoreRPG
#if !os(tvOS)
import GeneratorRPG
import PDFKit
#endif
import SwiftUI

public struct ViewController {
    public let sharingViewType: SharingViewType = .share
    public let thumbnailRowViewType: ThumbnailRowViewType = .photo
}

extension ViewController: ViewControllable {
    public var skipsHeaderEditorOnCreate: Bool { true }

    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel) -> AnyView {
        AnyView(InlineRowViewer(source: source, destination: destination).equatable())
    }

    @MainActor public func rowViewer(source: ItemRowModel, destination: ItemRowModel, sourceModel: (any ModelType)?, destinationModel: (any ModelType)?) -> AnyView {
        AnyView(InlineRowViewer(source: source, destination: destination, sourceModel: sourceModel).equatable())
    }
}

// MARK: - Batch Extraction

#if !os(tvOS)
extension ViewController {
    public var supportsBatchExtraction: Bool { true }

    @MainActor public func batchExtractionView(itemController: any ItemControllable, editController: any EditControllable, ids: [UUID]) -> AnyView? {
        guard let itemController = itemController as? ItemController,
              let editController = editController as? EditController else { return nil }
        return AnyView(
            BatchPdfSummaryExtractionView(
                module: .pdf,
                ids: ids,
                itemController: itemController,
                editController: editController,
                loadDocument: { itemId in
                    await itemController.pdfDocument(for: itemId)
                },
                addBookmarks: { sections, itemId, document in
                    editController.addExtractedBookmarks(sections, to: itemId) { position in
                        position > 0 ? document.page(at: position - 1)?.label : nil
                    }
                }
            )
        )
    }
}
#endif

// MARK: Viewer

public extension ViewController {
    @MainActor func linkListView(type: LinkRootType, itemSelectionModel: ItemSelectionModel) -> some View {
        LinkRootView(type: type, itemSelectionModel: itemSelectionModel)
    }

    @MainActor func viewer(root: PdfRootModel, itemId: UUID, entryId: UUID?, configuration: ViewerConfiguration, dismissAction: (() -> Void)? = nil) -> some View {
        let model = root.itemController.itemOrEmpty(for: itemId)
        return ViewerRootView(model: model, entryId: entryId, configuration: configuration, dismissAction: dismissAction)
    }
    }

public extension ViewController {
    @MainActor func gamePdfView(root: PdfRootModel) -> some View {
        ViewerRootView(model: root.gameController.currentItem(), entryId: nil, configuration: ViewerConfiguration(isGame: true), dismissAction: nil)
            .padding(32)
            .padding(.top, 64)
            .environment(root)
    }
}
