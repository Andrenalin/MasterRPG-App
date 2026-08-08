// @copyright André Trettin

import CoreRPG
import SnapshotTesting
import SwiftData
import SwiftUI
import Testing
@testable import CharacterRPG

@MainActor
@Suite(.disabled(if: SnapshotTestAvailability.isDisabledForCurrentXcode, "Snapshot tests are disabled on Xcode 26."), .serialized, .snapshots, .tags(.snapshot))
struct CharacterRPGDynamicPreviewSnapshotTests {
    // snapshot-root: CharacterRPG::DetailRootView
    @Test("DetailRootView")
    func detailRootView() async throws {
        try await assertPreviewSnapshot("DetailRootView") { root in
            ManagedNavigationStack {
                DetailRootView(
                    root: root,
                    model: root.itemController.itemOrEmpty(for: ValueModel.previewId)
                )
                .preferredColorScheme(.dark)
            }
        }
    }

    // snapshot-root: CharacterRPG::AddtionalEntryRow
    @Test("AddtionalEntryRow")
    func addtionalEntryRow() async throws {
        try await assertPreviewSnapshot("AddtionalEntryRow") { _ in
            let entry = ValueEntryModel.testEntryText
            AddtionalEntryRow(
                source: ItemRowModel(
                    itemId: ValueModel.previewId,
                    entryId: entry.id,
                    typeId: .value
                ),
                entry: entry,
                textModel: LinkHighlightTextModel(
                    linkControllable: nil,
                    text: "Hello Links",
                    highlightedText: "in",
                    toggler: nil,
                    shareResult: nil,
                    editAction: nil
                )
            )
            .padding()
        }
    }

    // snapshot-root: CharacterRPG::DetailFolderListView
    @Test("DetailFolderListView")
    func detailFolderListView() async throws {
        try await assertPreviewSnapshot("DetailFolderListView") { root in
            DetailFolderListView(
                root: root,
                model: root.itemController.itemOrEmpty(for: ValueModel.previewId),
                folderListController: root.folderListController
            )
        }
    }

    // snapshot-root: CharacterRPG::DetailListView
    @Test("DetailListView")
    func detailListView() async throws {
        try await assertPreviewSnapshot("DetailListView") { root in
            DetailListView(
                root: root,
                model: root.itemController.itemOrEmpty(for: ValueModel.previewId),
                folderListController: root.folderListController
            )
        }
    }

    private func assertPreviewSnapshot<Content: View>(
        _ name: String,
        @ViewBuilder content: (CharacterRootModel) -> Content
    ) async throws {
        let root = CharacterRootModel.previewFixture()
        let container = try await MockData.makeSharedContext()

        assertRepositorySnapshot(
            of: content(root)
                .environment(root)
                .environment(AppGameStateModel())
                .environment(AppWindowSizeModel())
                .environment(AppFocusModel())
                .environment(SearchBarVisibleModel())
                .environment(CacheItemListModel())
                .environment(ScenesManager())
                .environment(root.diceRoot)
                .environment(root.tableRoot)
                .environment(root.photoRoot)
                .environment(root.pdfRoot)
                .modifier(MockRootViewModifier())
                .modelContainer(container)
                .moduleTint(root.configurable.module)
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
