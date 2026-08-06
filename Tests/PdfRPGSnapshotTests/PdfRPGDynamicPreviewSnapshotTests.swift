// @copyright André Trettin

import CoreRPG
import GeneratorRPG
import PDFKit
import SnapshotTesting
import SwiftData
import SwiftUI
import Testing
@testable import PdfRPG

@MainActor
@Suite(.disabled(if: SnapshotTestAvailability.isDisabledForCurrentXcode, "Snapshot tests are disabled on Xcode 26."), .serialized, .snapshots, .tags(.snapshot))
struct PdfRPGDynamicPreviewSnapshotTests {
    // snapshot-root: PdfRPG::PdfContentView
    @Test("PdfContentView")
    func pdfContentView() async throws {
        try await assertDynamicSnapshot("PdfContentView") {
            PdfContentView(
                searchModel: PdfSearchModel(pdfDoc: PDFDocument()),
                horizontal: false,
                entry: nil
            )
        }
    }

    // snapshot-root: PdfRPG::SearchBar
    @Test("SearchBar")
    func searchBar() async throws {
        let searchModel = PdfSearchModel()
        searchModel.selectedEntry = PdfEntryModel(
            id: PdfRPGDynamicPreviewFixtures.entryID,
            name: "Forgotten Shrine",
            content: "This is the selected passage.",
            pageNumber: "2",
            bounds: .zero,
            displayState: 0
        )

        try await assertDynamicSnapshot("SearchBar") {
            NavigationStack {
                VStack {
                    SearchBar(searchModel: PdfSearchModel())
                    Spacer()
                    SearchBar(searchModel: searchModel)
                }
                .padding()
                .background(.blue.gradient)
            }
        }
    }

    // snapshot-root: PdfRPG::SelectionBar
    @Test("SelectionBar")
    func selectionBar() async throws {
        let root = PdfRootModel.preview
        let searchModel = PdfSearchModel()
        searchModel.selectedEntry = PdfEntryModel(
            id: PdfRPGDynamicPreviewFixtures.entryID,
            name: "Forgotten Shrine",
            content: "This is the selected passage.",
            pageNumber: "2",
            bounds: .zero,
            displayState: 0
        )

        try await assertDynamicSnapshot("SelectionBar") {
            NavigationStack {
                VStack {
                    SelectionBar(
                        editController: root.editController,
                        model: root.itemController.itemOrEmpty(for: PdfModel.previewId),
                        searchModel: searchModel,
                        withoutBookmark: false
                    )
                }
                .padding()
                .background(.red.gradient)
            }
        }
    }

    // snapshot-root: PdfRPG::DetailRootView
    @Test("DetailRootView")
    func detailRootView() async throws {
        let root = PdfRootModel.preview
        let model = root.itemController.itemOrEmpty(for: PdfModel.previewId)

        try await assertDynamicSnapshot("DetailRootView") {
            ManagedNavigationStack {
                DetailRootView(root: root, model: model)
                    .preferredColorScheme(.dark)
            }
        }
    }

    // snapshot-root: PdfRPG::ExtractToolBarButton
    @Test("ExtractToolBarButton")
    func extractToolBarButton() async throws {
        let root = PdfRootModel.preview

        try await assertDynamicSnapshot("ExtractToolBarButton") {
            ExtractToolBarButton(
                root: root,
                model: root.itemController.itemOrEmpty(for: PdfModel.previewId)
            )
            .padding()
        }
    }

    // snapshot-root: PdfRPG::DetailEditorView
    @Test("DetailEditorView")
    func detailEditorView() async throws {
        let root = PdfRootModel.preview

        try await assertDynamicSnapshot("DetailEditorView") {
            DetailEditorView(
                root: root,
                model: root.itemController.itemOrEmpty(for: PdfModel.previewId)
            )
        }
    }

    // snapshot-root: PdfRPG::DetailFolderListView
    @Test("DetailFolderListView")
    func detailFolderListView() async throws {
        let root = PdfRootModel.preview
        let model = root.itemController.itemOrEmpty(for: PdfModel.previewId)

        try await assertDynamicSnapshot("DetailFolderListView") {
            DetailFolderListView(
                root: root,
                model: model,
                folderListController: root.folderListController
            )
        }
    }

    // snapshot-root: PdfRPG::DetailListView
    @Test("DetailListView")
    func detailListView() async throws {
        let root = PdfRootModel.preview
        let model = root.itemController.itemOrEmpty(for: PdfModel.previewId)

        try await assertDynamicSnapshot("DetailListView") {
            ManagedNavigationStack {
                DetailListView(
                    root: root,
                    model: model,
                    folderListController: root.folderListController
                )
                .preferredColorScheme(.dark)
            }
        }
    }

    // snapshot-root: PdfRPG::SummaryPdfUpdateView
    @Test("SummaryPdfUpdateView")
    func summaryPdfUpdateView() async throws {
        try await assertDynamicSnapshot("SummaryPdfUpdateView") {
            SummaryPdfUpdateView(
                content: PdfSummaryAnalysis(
                    title: "Dungeons & Dragons Player's Handbook",
                    summary: "Core rules for creating characters and playing an adventure.",
                    tags: ["Fantasy", "Rulebook", "Character Creation"],
                    sections: [
                        PdfSection(
                            heading: "Step-by-Step Characters",
                            summary: "A guide to creating a character.",
                            pageNumber: 11
                        ),
                        PdfSection(
                            heading: "Classes",
                            summary: "Character classes and their abilities.",
                            pageNumber: 45
                        )
                    ]
                ),
                selectedProperties: .constant(PdfPropertySelection())
            )
        }
    }

    private func assertDynamicSnapshot<Content: View>(
        _ name: String,
        @ViewBuilder content: () -> Content
    ) async throws {
        let container = try await PdfRPGDynamicPreviewSnapshotFixtureCache.modelContainer()
        assertRepositorySnapshot(
            of: content()
                .modifier(MockRootViewModifier(modelContext: container.mainContext))
                .environment(AppFocusModel())
                .modelContainer(container)
                .deterministicSnapshotEnvironment()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background),
            as: .image(
                perceptualPrecision: 0.98,
                layout: .fixed(width: 390, height: 844)
            ),
            named: name
        )
    }
}

private enum PdfRPGDynamicPreviewFixtures {
    static let entryID = UUID(uuid: (0xB2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
}

@MainActor
private enum PdfRPGDynamicPreviewSnapshotFixtureCache {
    private static var cachedContainer: ModelContainer?

    static func modelContainer() async throws -> ModelContainer {
        if let cachedContainer {
            return cachedContainer
        }
        let container = try await MockData.makeSharedContext()
        cachedContainer = container
        return container
    }
}
