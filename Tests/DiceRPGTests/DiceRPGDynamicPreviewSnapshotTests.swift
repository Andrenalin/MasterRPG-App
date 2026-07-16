// @copyright André Trettin

import CoreRPG
import Foundation
import SnapshotTesting
import SwiftData
import SwiftUI
import Testing
@testable import DiceRPG

@MainActor
@Suite(.serialized, .snapshots, .tags(.snapshot))
struct DiceRPGDynamicPreviewSnapshotTests {
    // snapshot-root: DiceRPG::DicePlayer
    @Test("DicePlayer")
    func dicePlayer() async throws {
        try await assertPreviewSnapshot("DicePlayer") { _ in
            DicePlayer(filterout: DiceModel.previewId, alignment: .leading)
                .environment(DiceDisplayModel())
                .padding()
        }
    }

    // snapshot-root: DiceRPG::CoupEditor
    @Test("CoupEditor")
    func coupEditor() async throws {
        try await assertPreviewSnapshot("CoupEditor") { root in
            CoupEditor(model: root.itemController.itemOrEmpty(for: DiceModel.previewId))
        }
    }

    // snapshot-root: DiceRPG::DiceEditor
    @Test("DiceEditor")
    func diceEditor() async throws {
        try await assertPreviewSnapshot("DiceEditor") { root in
            DiceEditor(model: root.itemController.itemOrEmpty(for: DiceModel.previewId))
        }
    }

    // snapshot-root: DiceRPG::DiceOptionEditor
    @Test("DiceOptionEditor")
    func diceOptionEditor() async throws {
        try await assertPreviewSnapshot("DiceOptionEditor") { root in
            DiceOptionEditor(model: root.itemController.itemOrEmpty(for: DiceModel.previewId))
        }
    }

    // snapshot-root: DiceRPG::FumbleEditor
    @Test("FumbleEditor")
    func fumbleEditor() async throws {
        try await assertPreviewSnapshot("FumbleEditor") { root in
            FumbleEditor(model: root.itemController.itemOrEmpty(for: DiceModel.previewId))
        }
    }

    // snapshot-root: DiceRPG::RerollEditor
    @Test("RerollEditor")
    func rerollEditor() async throws {
        try await assertPreviewSnapshot("RerollEditor") { root in
            RerollEditor(model: root.itemController.itemOrEmpty(for: DiceModel.previewId))
        }
    }

    // snapshot-root: DiceRPG::SpecialOptionEditor
    @Test("SpecialOptionEditor")
    func specialOptionEditor() async throws {
        try await assertPreviewSnapshot("SpecialOptionEditor") { root in
            SpecialOptionEditor(model: root.itemController.itemOrEmpty(for: DiceModel.previewId))
        }
    }

    // snapshot-root: DiceRPG::ToggleDiceValue
    @Test("ToggleDiceValue")
    func toggleDiceValue() async throws {
        try await assertPreviewSnapshot("ToggleDiceValue") { root in
            ToggleDiceValue(
                model: root.itemController.itemOrEmpty(for: DiceModel.previewId),
                toggleKetpath: \.sumUp
            )
            .padding()
        }
    }

#if !os(tvOS)
    // snapshot-root: DiceRPG::RollResultSnippetView
    @Test("RollResultSnippetView")
    func rollResultSnippetView() async throws {
        let result = DiceResultModel(
            diceModel: DiceModel.previewSnapshot,
            result: .coup,
            values: "1",
            sum: 1,
            checked: true,
            timeStamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try await assertPreviewSnapshot("RollResultSnippetView") { _ in
            RollResultSnippetView(result: result)
                .background(.black)
        }
    }
#endif

    // snapshot-root: DiceRPG::DetailRootView
    @Test("DetailRootView")
    func detailRootView() async throws {
        try await assertPreviewSnapshot("DetailRootView") { root in
            ManagedNavigationStack {
                DetailRootView(
                    root: root,
                    model: root.itemController.itemOrEmpty(for: DiceModel.previewId)
                )
                .preferredColorScheme(.dark)
            }
        }
    }

    // snapshot-root: DiceRPG::ViewerRootView
    @Test("ViewerRootView")
    func viewerRootView() async throws {
        try await assertPreviewSnapshot("ViewerRootView") { root in
            ManagedNavigationStack {
                ViewerRootView(
                    model: root.itemController.itemOrEmpty(for: DiceModel.previewId),
                    configuration: ViewerConfiguration(closeButton: true),
                    dismissAction: nil
                )
            }
        }
    }

    // snapshot-root: DiceRPG::DetailEditorView
    @Test("DetailEditorView")
    func detailEditorView() async throws {
        try await assertPreviewSnapshot("DetailEditorView") { root in
            DetailEditorView(model: root.itemController.itemOrEmpty(for: DiceModel.previewId))
        }
    }

    // snapshot-root: DiceRPG::DetailFolderListView
    @Test("DetailFolderListView")
    func detailFolderListView() async throws {
        try await assertPreviewSnapshot("DetailFolderListView") { root in
            DetailFolderListView(
                root: root,
                model: root.itemController.itemOrEmpty(for: DiceModel.previewId),
                folderListController: root.folderListController
            )
        }
    }

    // snapshot-root: DiceRPG::DetailListView
    @Test("DetailListView")
    func detailListView() async throws {
        try await assertPreviewSnapshot("DetailListView") { root in
            DetailListView(
                root: root,
                model: root.itemController.itemOrEmpty(for: DiceModel.previewId),
                folderListController: root.folderListController
            )
        }
    }

    // snapshot-root: DiceRPG::DiceBag
    @Test("DiceBag")
    func diceBag() async throws {
        try await assertPreviewSnapshot("DiceBag") { root in
            DiceBag(model: root.itemController.itemOrEmpty(for: DiceModel.previewId))
                .padding()
        }
    }

    // snapshot-root: DiceRPG::DiceOverlayView
    @Test("DiceOverlayView")
    func diceOverlayView() async throws {
        try await assertPreviewSnapshot("DiceOverlayView") { root in
            DiceOverlayView(model: root.itemController.itemOrEmpty(for: DiceModel.previewId))
        }
    }

    // snapshot-root: DiceRPG::DiceViewer
    @Test("DiceViewer")
    func diceViewer() async throws {
        try await assertPreviewSnapshot("DiceViewer") { root in
            DiceViewer(
                model: root.itemController.itemOrEmpty(for: DiceModel.previewId),
                isEditor: true
            )
        }
    }

    // snapshot-root: DiceRPG::ThumbnailDice
    @Test("ThumbnailDice")
    func thumbnailDice() async throws {
        try await assertPreviewSnapshot("ThumbnailDice") { _ in
            HStack {
                ThumbnailDice(die: DiceModel.previewSnapshot.dice[0], withoutResult: false)
                ThumbnailDice(die: .die10(color: .G), withoutResult: false)
            }
            .padding()
        }
    }

    // snapshot-root: DiceRPG::ThumbnailDiceRow
    @Test("ThumbnailDiceRow")
    func thumbnailDiceRow() async throws {
        try await assertPreviewSnapshot("ThumbnailDiceRow") { _ in
            HStack {
                ThumbnailDiceRow(itemId: DiceModel.previewId)
                ThumbnailDiceRow(itemId: DiceModel.uuidCoC)
            }
            .padding()
        }
    }

#if os(visionOS)
    // snapshot-root: DiceRPG::DiceSpace
    @Test("DiceSpace")
    func diceSpace() async throws {
        try await assertPreviewSnapshot("DiceSpace") { root in
            DiceSpace(root: root)
        }
    }

    // snapshot-root: DiceRPG::ShowDiceSpace
    @Test("ShowDiceSpace")
    func showDiceSpace() async throws {
        try await assertPreviewSnapshot("ShowDiceSpace") { root in
            ShowDiceSpace(
                root: root,
                itemId: DiceModel.previewId,
                viewModel: DiceSpaceModel()
            )
            .padding()
        }
    }
#endif

    private func assertPreviewSnapshot<Content: View>(
        _ name: String,
        @ViewBuilder content: (DiceRootModel) -> Content
    ) async throws {
        let root = DiceRootModel.previewFixture()
        let container = try await MockData.makeSharedContext()

        assertRepositorySnapshot(
            of: content(root)
                .modifier(MockRootViewModifier(root: root))
                .modelContainer(container)
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
                .tint(root.configurable.module.tint)
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
