// @copyright André Trettin

import CoreRPG
import SnapshotTesting
import SwiftData
import SwiftUI
import Testing
@testable import GeneratorRPG

@MainActor
@Suite(.disabled(if: SnapshotTestAvailability.isDisabledForCurrentXcode, "Snapshot tests are disabled on Xcode 26."), .serialized, .snapshots, .tags(.snapshot))
struct GeneratorRPGDynamicPreviewSnapshotTests {
    // snapshot-root: GeneratorRPG::ChatInputView
    @Test("ChatInputView")
    func chatInputView() async throws {
        try await assertDynamicSnapshot("ChatInputView") {
            GeneratorFocusSnapshotHarness { focus in
                ChatInputView(
                    messageText: .constant("Describe a forgotten shrine"),
                    generatorController: AdventureGeneratorController(),
                    isTextFieldFocused: focus,
                    sendMessageAction: { _ in }
                )
            }
        }
    }

    // snapshot-root: GeneratorRPG::AdventureChatComposerBar
    @Test("AdventureChatComposerBar")
    func adventureChatComposerBar() async throws {
        let root = GeneratorRootModel.previewFixture()
        let controller = root.generatorController(
            for: .adventure,
            itemId: AdventureChatPreviewData.sheetModel.source.itemId
        )

        try await assertDynamicSnapshot("AdventureChatComposerBar", root: root) {
            GeneratorFocusSnapshotHarness { focus in
                AdventureChatComposerBar(
                    prompt: .constant("Add a hidden rival"),
                    generatorController: controller,
                    isTextFieldFocused: focus,
                    canExtract: true,
                    isExtracting: false,
                    prepareForRequestAction: {},
                    requestBlocksAction: { _ in },
                    extractAction: {}
                )
            }
        }
    }

    // snapshot-root: GeneratorRPG::AdventureGenRootView
    @Test("AdventureGenRootView")
    func adventureGenRootView() async throws {
        let root = GeneratorRootModel.previewFixture()
        let model = try #require(root.itemController.itemSync(for: GeneratorModel.previewId))

        try await assertDynamicSnapshot("AdventureGenRootView", root: root) {
            NavigationStack {
                AdventureGenRootView(model: model, dismissAction: {})
            }
        }
    }

    // snapshot-root: GeneratorRPG::ChatSheetRootView
    @Test("ChatSheetRootView")
    func chatSheetRootView() async throws {
        let root = GeneratorRootModel.previewFixture()
        let sheetModel = AdventureChatPreviewData.sheetModel
        let sheetRootController = try #require(
            root.rootManager?.itemRootController(for: .adventure)
        )
        let rootManager = try #require(sheetRootController.rootManager)
        let generatorController = root.generatorController(
            for: .adventure,
            itemId: sheetModel.source.itemId
        )
        let sheetRootModel = SheetRootModel(
            rootManager: rootManager,
            linkControllable: sheetRootController.linkControllable,
            sheetControllable: sheetRootController.sheetControllable,
            sheetModel: sheetModel,
            isEditor: false
        )

        try await assertDynamicSnapshot("ChatSheetRootView", root: root) {
            GeneratorFocusSnapshotHarness { focus in
                ChatSheetRootView(
                    sheetRootController: sheetRootController,
                    sheetRootModel: sheetRootModel,
                    sheetModel: sheetModel,
                    model: generatorController.model,
                    generatorController: generatorController,
                    activeAnswerParentSource: nil,
                    prompt: .constant("Add a dangerous discovery."),
                    isTextFieldFocused: focus,
                    prepareForRequestAction: {},
                    requestBlocksAction: { _ in },
                    extractAction: {},
                    requestSheetDetailAction: { _ in }
                )
            }
        }
    }

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

    // snapshot-root: GeneratorRPG::SheetAIAssistantComposer
    @Test("SheetAIAssistantComposer")
    func sheetAIAssistantComposer() async throws {
        try await assertDynamicSnapshot("SheetAIAssistantComposer") {
            GeneratorNamespaceSnapshotHarness { namespace in
                GeneratorFocusSnapshotHarness { focus in
                    SheetAIAssistantComposer(
                        module: .adventure,
                        messageText: .constant("Create a dramatic encounter"),
                        availability: SheetAIGenerationController().availability,
                        isGenerating: false,
                        isTextFieldFocused: focus,
                        glassNamespace: namespace,
                        submitAction: {},
                        closeAction: {}
                    )
                }
            }
        }
    }

    // snapshot-root: GeneratorRPG::SheetAIAssistantOpenButton
    @Test("SheetAIAssistantOpenButton")
    func sheetAIAssistantOpenButton() async throws {
        try await assertDynamicSnapshot("SheetAIAssistantOpenButton") {
            GeneratorNamespaceSnapshotHarness { namespace in
                SheetAIAssistantOpenButton(
                    module: .adventure,
                    glassNamespace: namespace,
                    action: {}
                )
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
