// @copyright André Trettin

import CoreRPG
import PDFKit
import SnapshotTesting
import SwiftData
import SwiftUI
import Testing
@testable import GeneratorRPG

@MainActor
@Suite(.disabled(if: SnapshotTestAvailability.isDisabledForCurrentXcode, "Snapshot tests are disabled on Xcode 26."), .serialized, .snapshots, .tags(.snapshot))
struct GeneratorRPGViewSnapshotTests {
    // snapshot-root: GeneratorRPG::GeneratorRootView
    @Test("Generator root")
    func generatorRoot() async throws {
        try await assertMockSnapshot(
            ManagedNavigationStack {
                GeneratorRootView(restoresState: false)
            },
            name: "GeneratorRoot",
            height: 844
        )
    }

    // snapshot-root: GeneratorRPG::TextSummaryExtractionView
    @Test("Text summary extraction")
    func textSummaryExtraction() {
        assertViewSnapshot(
            NavigationStack {
                TextSummaryExtractionView(
                    module: .table,
                    entriesText: "A moss-covered altar conceals a rune-marked compartment."
                ) { _, _ in }
            },
            name: "TextSummaryExtraction",
            height: 720
        )
    }

    // snapshot-root: GeneratorRPG::PdfContentExtractionView
    @Test("PDF content extraction")
    func pdfContentExtraction() {
        assertViewSnapshot(
            PdfContentExtractionView(pdfDocument: PDFDocument()) { _ in },
            name: "PdfContentExtraction",
            height: 640
        )
    }

    // snapshot-root: GeneratorRPG::TableSummaryAnalysisView
    @Test("Table summary analysis")
    func tableSummaryAnalysis() {
        assertViewSnapshot(
            TableSummaryAnalysisView(
                entriesText: "1-2: Silent sentries. 3-4: A flooded archive. 5-6: The bronze key."
            ) { _ in },
            name: "TableSummaryAnalysis",
            height: 640
        )
    }

    // snapshot-root: GeneratorRPG::SheetAIAssistantOverlayView
    @Test("Sheet AI assistant")
    func sheetAIAssistant() {
        assertViewSnapshot(
            SheetAIAssistantOverlayView(generatorController: GeneratorController(), rootModel: .fake),
            name: "SheetAIAssistant",
            height: 720
        )
    }

    private func assertMockSnapshot<Content: View>(
        _ content: Content,
        name: String,
        height: CGFloat
    ) async throws {
        let container = try await MockData.makeSharedContext()
        assertViewSnapshot(
            content
                .modifier(MockRootViewModifier())
                .environment(AppFocusModel())
                .environment(SearchBarVisibleModel())
                .modelContainer(container),
            name: name,
            height: height
        )
    }

    private func assertViewSnapshot<Content: View>(
        _ content: Content,
        name: String,
        height: CGFloat
    ) {
        assertRepositorySnapshot(
            of: content
                .deterministicSnapshotEnvironment()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background),
            as: .image(
                perceptualPrecision: 0.98,
                layout: .fixed(width: 390, height: height)
            ),
            named: name
        )
    }
}
