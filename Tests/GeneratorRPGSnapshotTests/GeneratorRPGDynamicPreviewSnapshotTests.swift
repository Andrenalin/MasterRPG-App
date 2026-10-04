// @copyright André Trettin

import CoreRPG
import SnapshotTesting
import SwiftData
import SwiftUI
import Testing
@testable import GeneratorRPG

@MainActor
@Suite(.serialized, .snapshots, .tags(.snapshot))
struct GeneratorRPGDynamicPreviewSnapshotTests {
    // snapshot-root: GeneratorRPG::DetailListView
    @Test("DetailListView")
    func detailListView() async throws {
        let root = GeneratorRootModel.previewFixture()
        let model = try #require(root.itemController.itemSync(for: GeneratorModel.previewId))

        try await assertDynamicSnapshot("DetailListView", root: root) {
            DetailListView(root: root, model: model)
        }
    }

    // snapshot-root: GeneratorRPG::DetailRootView
    @Test("DetailRootView")
    func detailRootView() async throws {
        let root = GeneratorRootModel.previewFixture()
        let model = try #require(root.itemController.itemSync(for: GeneratorModel.previewId))

        try await assertDynamicSnapshot("DetailRootView", root: root) {
            ManagedNavigationStack {
                DetailRootView(root: root, model: model)
            }
        }
    }

    // snapshot-root: GeneratorRPG::SheetAIAssistantStandardControl
    @Test("SheetAIAssistantStandardControl")
    func sheetAIAssistantComposer() async throws {
        try await assertDynamicSnapshot("SheetAIAssistantStandardControl") {
            GeneratorNamespaceSnapshotHarness { namespace in
                GeneratorFocusSnapshotHarness { focus in
                    SheetAIAssistantStandardControl(
                        generatorController: GeneratorController(),
                        module: .adventure,
                        messageText: .constant("Create a dramatic encounter"),
                        isExpanded: true,
                        isTextFieldFocused: focus,
                        submitAction: {},
                        toggleAction: {}
                    )
                }
            }
        }
    }

    // snapshot-root: GeneratorRPG::TextSummaryUpdateView
    @Test("TextSummaryUpdateView")
    func textSummaryUpdateView() async throws {
        try await assertDynamicSnapshot("TextSummaryUpdateView") {
            TextSummaryUpdateView(
                content: TableSummaryAnalysis(
                    title: "Forgotten Shrine Encounters",
                    description: "Potential discoveries and dangers within an ancient shrine.",
                    tags: ["ruins", "mystery"]
                ),
                module: .table,
                selectedProperties: .constant(TextSummaryPropertySelection())
            )
        }
    }

    private func assertDynamicSnapshot<Content: View>(
        _ name: String,
        root: GeneratorRootModel = .previewFixture(),
        @ViewBuilder content: () -> Content
    ) async throws {
        let container = try await GeneratorRPGDynamicPreviewSnapshotFixtureCache.modelContainer()
        assertRepositorySnapshot(
            of: content()
                .modifier(MockRootViewModifier(root: root))
                .environment(AppFocusModel())
                .environment(SearchBarVisibleModel())
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

@MainActor
private struct GeneratorFocusSnapshotHarness<Content: View>: View {
    @FocusState private var isFocused: Bool
    private let content: (FocusState<Bool>.Binding) -> Content

    init(@ViewBuilder content: @escaping (FocusState<Bool>.Binding) -> Content) {
        self.content = content
    }

    var body: some View {
        content($isFocused)
    }
}

@MainActor
private struct GeneratorNamespaceSnapshotHarness<Content: View>: View {
    @Namespace private var namespace
    private let content: (Namespace.ID) -> Content

    init(@ViewBuilder content: @escaping (Namespace.ID) -> Content) {
        self.content = content
    }

    var body: some View {
        content(namespace)
    }
}

@MainActor
private enum GeneratorRPGDynamicPreviewSnapshotFixtureCache {
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
