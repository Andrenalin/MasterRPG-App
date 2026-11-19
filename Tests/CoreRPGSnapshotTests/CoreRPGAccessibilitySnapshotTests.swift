// @copyright André Trettin

// CODE_AUDIT_TestGaps §8.6: the same views as the reviewed baseline, rendered at the accessibility3
// text size, so a layout that clips or overlaps at large Dynamic Type shows up in review. The fixtures
// are copies of the generated preview snapshots of the same names; the baseline images live next to
// the other references of this target.

import Foundation
import SnapshotTesting
import SwiftData
import SwiftUI
import Testing
import CoreGraphics
import UniformTypeIdentifiers
@testable import CoreRPG

@MainActor
@Suite(.serialized, .snapshots, .tags(.snapshot))
struct CoreRPGAccessibilitySnapshotTests {
    @Test("GlassButton at accessibility size")
    func snapshotGlassButtonAccessibility3() async throws {
        try await assertAccessibilitySnapshot("GlassButton-accessibility3") {
            CoreRPG.GlassButton(action: {}) {
                Label {
                    Text(verbatim: "Continue")
                } icon: {
                    Image(systemName: "arrow.right")
                }
            }
        }
    }

    @Test("InlineEditorView at accessibility size")
    func snapshotInlineEditorViewAccessibility3() async throws {
        try await assertAccessibilitySnapshot("InlineEditorView-accessibility3") {
            CoreRPG.InlineEditorView(
                entryDataEditable: FakeEditController.fake,
                updateHandler: { _ in },
                entry: SheetModel(
                    source: ItemRowModel(itemId: .fixture1, entryId: .fixture2, typeId: .none),
                    editType: .number,
                    name: "Armor Class",
                    description: "A deterministic inline editor.",
                    entries: []
                )
            )
            .padding()
        }
    }

    @Test("TextDoubleEditor at accessibility size")
    func snapshotTextDoubleEditorAccessibility3() async throws {
        try await assertAccessibilitySnapshot("TextDoubleEditor-accessibility3") {
            let title = LocalizedStringKey(String("Scale"))
            CoreRPG.TextDoubleEditor(
                model: EditIdentifierModel(value: 2.5),
                title: title,
                icon: "slider.horizontal.3",
                prompt: title,
                bundle: nil,
                range: 0...5
            )
            .padding()
        }
    }

    @Test("ToggleEditor at accessibility size")
    func snapshotToggleEditorAccessibility3() async throws {
        try await assertAccessibilitySnapshot("ToggleEditor-accessibility3") {
            let title = LocalizedStringKey(String("Visible"))
            CoreRPG.ToggleEditor(model: EditIdentifierModel(value: true), title: title, bundle: nil, icon: "eye")
                .padding()
        }
    }

    @Test("ValuePickerEditor at accessibility size")
    func snapshotValuePickerEditorAccessibility3() async throws {
        try await assertAccessibilitySnapshot("ValuePickerEditor-accessibility3") {
            let title = LocalizedStringKey(String("Rank"))
            CoreRPG.ValuePickerEditor(
                model: EditIdentifierModel(value: ValuePickerPreviewOption.veteran),
                allCategories: ValuePickerPreviewOption.allCases,
                title: title,
                bundle: nil
            ) { option in
                Text(option.rawValue.capitalized)
            }
            .padding()
        }
    }

    @Test("GroupEditorView at accessibility size")
    func snapshotGroupEditorViewAccessibility3() async throws {
        try await assertAccessibilitySnapshot("GroupEditorView-accessibility3") {
            CoreRPG.GroupEditorView(
                groupEditorController: GroupEditorController(
                    itemController: FakeItemController.fake,
                    editController: FakeEditController.fake,
                    ids: [UUID()]
                )
            )
        }
    }

    @Test("ItemRowView at accessibility size")
    func snapshotItemRowViewAccessibility3() async throws {
        try await assertAccessibilitySnapshot("ItemRowView-accessibility3") {
            CoreRPG.ItemRowView(
                root: ItemRootController.fake,
                model: FakeItemModel(id: .fixture1, name: "Goblin Ambush", description: "A narrow bridge guarded by goblins.", tags: ["Encounter", "Dungeon"]),
                cacheItemListModel: CacheItemListModel(),
                listDisplayModel: ListDisplayModel(),
                searchModel: .preview()
            )
            .padding()
            .environment(AppGameStateModel())
            .environment(\.locale, .init(identifier: "de"))
        }
    }

    @Test("ItemRootListView at accessibility size")
    func snapshotItemRootListViewAccessibility3() async throws {
        try await assertAccessibilitySnapshot("ItemRootListView-accessibility3") {
            CoreRPG.ItemRootListView(root: ItemRootController.fake)
                .environment(AppFocusModel())
        }
    }

    @Test("EntryEditRow at accessibility size")
    func snapshotEntryEditRowAccessibility3() async throws {
        try await assertAccessibilitySnapshot("EntryEditRow-accessibility3") {
            let fixture = FakeItemRootControllerFixture()
            CoreRPG.EntryEditRow(
                root: fixture.root,
                editController: fixture.editController,
                itemId: .fixture1,
                entry: FakeEntryModel.empty,
                cacheItemListModel: CacheItemListModel(),
                listDisplayModel: ListDisplayModel(),
                searchModel: fixture.searchController.searchModel
            )
            .padding()
        }
    }

    @Test("CategoryItemRow at accessibility size")
    func snapshotCategoryItemRowAccessibility3() async throws {
        try await assertAccessibilitySnapshot("CategoryItemRow-accessibility3") {
            CoreRPG.CategoryItemRow(category: ItemListCategory.adventure)
        }
    }

    private func assertAccessibilitySnapshot<Content: View>(
        _ name: String,
        @ViewBuilder content: () -> Content
    ) async throws {
        let appGameStateModel = AppGameStateModel()
        assertRepositorySnapshot(
            of: content()
                .environment(appGameStateModel)
                .environment(AppNavigationModel(appGameStateModel: appGameStateModel))
                .environment(AppSettingsModel.previewFixture())
                .environment(AppWindowSizeModel())
                .environment(AppFocusModel())
                .environment(SearchBarVisibleModel())
                .environment(ScenesManager())
                .environment(GroupItemSelectionModel())
                .environment(ItemRootController.previewFixture())
                .cloudKitAccountChecksEnabled(false)
                .itemStateRestorationEnabled(false)
                .meshAnimationEnabled(false)
                .deterministicSnapshotEnvironment(dynamicTypeSize: .accessibility3)
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background),
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.98,
                layout: .fixed(width: 390, height: 844)
            ),
            named: name
        )
    }
}
