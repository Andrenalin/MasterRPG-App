// @copyright André Trettin

import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import CoreRPG

@MainActor
@Suite(.serialized, .snapshots, .tags(.snapshot))
struct CoreRPGDynamicPreviewSnapshotTests {
    // snapshot-root: CoreRPG::ControlSharingView
    @Test("ControlSharingView")
    func controlSharingView() {
        let controls = [
            SharingControlModel(id: .fixture1, name: "Mega", show: true)
        ]

        assertCoreSnapshot("ControlSharingView") {
            NavigationStack {
                Color.blue
                    .toolbar {
                        ControlSharingView(alignment: .bottomTrailing, action: {})
                            .environment(
                                \.sharingControlActions,
                                SharingControlActions(
                                    control: { controls },
                                    update: { _ in }
                                )
                            )
                    }
            }
            .environment(AppGameStateModel())
        }
    }

    // snapshot-root: CoreRPG::QuickEditorButtonView
    @Test("QuickEditorButtonView")
    func quickEditorButtonView() {
        assertCoreSnapshot("QuickEditorButtonView") {
            VStack(spacing: 25) {
                QuickEditorButtonView(number: .constant(1), value: 1, title: "1", isAddition: true)
                QuickEditorButtonView(number: .constant(2), value: 2, title: "2", isAddition: true)
                QuickEditorButtonView(number: .constant(5), value: 5, title: "5", isAddition: true)
                QuickEditorButtonView(number: .constant(10), value: 10, title: "10", isAddition: false)
            }
            .padding()
        }
    }

    // snapshot-root: CoreRPG::QuickEditorDoubleView
    @Test("QuickEditorDoubleView")
    func quickEditorDoubleView() {
        assertCoreSnapshot("QuickEditorDoubleView") {
            QuickEditorDoubleView(number: .constant(12.5))
                .padding()
        }
    }

    // snapshot-root: CoreRPG::QuickEditorIntView
    @Test("QuickEditorIntView")
    func quickEditorIntView() {
        assertCoreSnapshot("QuickEditorIntView") {
            QuickEditorIntView(number: .constant(12))
                .padding()
        }
    }

    // snapshot-root: CoreRPG::SendControlView
    @Test("SendControlView")
    func sendControlView() {
        assertCoreSnapshot("SendControlView") {
            SendControlView(
                controls: .constant([
                    SharingControlModel(id: .fixture1, name: "Alice", show: true),
                    SharingControlModel(id: .fixture2, name: "Bob", show: false)
                ])
            )
        }
    }

    // snapshot-root: CoreRPG::AddTagsEditor
    @Test("AddTagsEditor")
    func addTagsEditor() {
        assertCoreSnapshot("AddTagsEditor") {
            AddTagsEditor(tags: .constant(["Dungeon"]))
                .padding()
        }
    }

    // snapshot-root: CoreRPG::QuickLinkEditor
    @Test("QuickLinkEditor")
    func quickLinkEditor() {
        let entries = [
            QuickLinkPreviewEntry(textLinkContent: "The forgotten shrine awaits.")
        ]

        assertCoreSnapshot("QuickLinkEditor") {
            QuickLinkEditor(
                editController: FakeEditController.fake,
                linkController: FakeLinkController.fake,
                model: .constant(entries),
                title: "Quick Links"
            ) { afterEntries in
                Button("Scan Links") {
                    afterEntries.wrappedValue = [
                        QuickLinkPreviewEntry(
                            textLinkContent: "The [forgotten shrine](RPG://ADVENTURE/preview) awaits."
                        )
                    ]
                }
                .padding()
            }
        }
    }

    // snapshot-root: CoreRPG::RemoveTagsEditor
    @Test("RemoveTagsEditor")
    func removeTagsEditor() {
        assertCoreSnapshot("RemoveTagsEditor") {
            RemoveTagsEditor(tags: .constant(["Dungeon", "Mystery", "Undead"]))
                .padding()
        }
    }

    // snapshot-root: CoreRPG::EntryContentEditor
    @Test("EntryContentEditor")
    func entryContentEditor() {
        let model = TextEditModel(linkRegisterController: nil)
        model.text = "Sample content with [link](test)"
        model.resetAttributedText()

        assertCoreSnapshot("EntryContentEditor") {
            CoreRPGFocusSnapshotHarness(EntryEditorFocusField.self) { focus in
                EntryContentEditor(editModel: model, currentFocus: focus)
                    .padding()
            }
            .background(.background)
            .preferredColorScheme(.light)
        }
    }

    // snapshot-root: CoreRPG::EntryEditorHeaderView
    @Test("EntryEditorHeaderView")
    func entryEditorHeaderView() {
        let editModel = TextEditModel(linkRegisterController: LinkRegisterController.fake)

        assertCoreSnapshot("EntryEditorHeaderView") {
            EntryEditorHeaderView(
                editController: FakeEditController.fake,
                editorModel: SheetEditorModel(),
                itemId: .fixture1,
                editModel: editModel,
                entry: FakeEntryModel.empty,
                linkTypes: EmptyLinkTransferable.self
            )
        }
    }

    // snapshot-root: CoreRPG::EntryNameEditor
    @Test("EntryNameEditor")
    func entryNameEditor() {
        let model = TextEditModel(linkRegisterController: nil)

        assertCoreSnapshot("EntryNameEditor") {
            CoreRPGFocusSnapshotHarness(EntryEditorFocusField.self) { focus in
                EntryNameEditor(editModel: model, currentFocus: focus)
                    .padding()
            }
            .background(Color.black)
            .preferredColorScheme(.dark)
        }
    }

    // snapshot-root: CoreRPG::TextEditorLinkView
    @Test("TextEditorLinkView")
    func textEditorLinkView() {
        let model = TextEditModel(linkRegisterController: .fake)
        model.name = "Hello"
        model.text = "Long Text"
        model.resetAttributedText()

        assertCoreSnapshot("TextEditorLinkView") {
            Color.clear
                .background {
                    Rectangle().fill(Color.blue.gradient)
                }
                .overlay {
                    TextEditorLinkView(model: model, maxHeight: 200)
                        .padding()
                }
        }
    }

    // snapshot-root: CoreRPG::FileBrowserPickerView
    @Test("FileBrowserPickerView")
    func fileBrowserPickerView() {
        assertCoreSnapshot("FileBrowserPickerView") {
            FileBrowserPickerView(
                shown: .constant(false),
                pickerType: .open,
                fileNameSuggestion: "adventure.pdf",
                handler: { _ in }
            )
        }
    }

    // snapshot-root: CoreRPG::ImportChooseUrlView
    @Test("ImportChooseUrlView")
    func importChooseUrlView() {
        assertCoreSnapshot("ImportChooseUrlView") {
            ImportChooseUrlView(
                showImportFileChooser: .constant(false),
                loadUrl: .constant(nil),
                proposedUrl: .constant(nil),
                urlProvider: FakeExampleUrlProvider(),
                isSaveGame: false,
                importModel: ItemDataImportModel()
            )
            .padding()
        }
    }

    // snapshot-root: CoreRPG::ImportReviewItemListView
    @Test("ImportReviewItemListView")
    func importReviewItemListView() throws {
        let module = try #require(ImportReviewModel.preview.modules.first)

        assertCoreSnapshot("ImportReviewItemListView") {
            ImportReviewItemListView(module: module, selectedID: .constant(nil))
        }
    }

    // snapshot-root: CoreRPG::ImportStatusSection
    @Test("ImportStatusSection")
    func importStatusSection() {
        assertCoreSnapshot("ImportStatusSection") {
            ImportStatusSection(
                outcome: .notStarted,
                importModel: ItemDataImportModel(),
                showImportFileChooser: .constant(false),
                loadUrl: .constant(nil),
                proposedUrl: .constant(nil),
                urlProvider: FakeExampleUrlProvider(),
                isSaveGame: false
            )
            .padding()
        }
    }

    // snapshot-root: CoreRPG::ItemDetailContentView
    @Test("ItemDetailContentView")
    func itemDetailContentView() {
        assertCoreSnapshot("ItemDetailContentView") {
            ItemDetailContentView<Text, EmptyLinkTransferable>(
                root: ItemRootController.fake,
                model: FakeItemModel.empty,
                configuration: .init(),
                editor: Text("Editor content"),
                headerModel: HeaderScrollModel(),
                folderListController: FakeFolderListController.fake,
                editingItem: .constant(nil)
            )
            .environment(AppGameStateModel())
        }
    }

    // snapshot-root: CoreRPG::ModalPresentCloseButton
    @Test("ModalPresentCloseButton")
    func modalPresentCloseButton() {
        assertCoreSnapshot("ModalPresentCloseButton") {
            ModalPresentCloseButton(isPresented: .constant(true))
        }
    }

    // snapshot-root: CoreRPG::HeaderContentScrollView
    @Test("HeaderContentScrollView")
    func headerContentScrollView() {
        assertCoreSnapshot("HeaderContentScrollView") {
            HeaderContentScrollView(
                model: HeaderScrollModel(),
                backgroundColor: .orange
            ) {
                HStack {
                    Image(systemName: "chevron.left")
                    Spacer()
                    Text("Apple Store")
                }
                .padding()
            } content: {
                Form {
                    ForEach(1...12, id: \.self) { index in
                        Text("Adventure row \(index)")
                    }
                }
            }
        }
    }

    // snapshot-root: CoreRPG::HeaderFooterContentScrollView
    @Test("HeaderFooterContentScrollView")
    func headerFooterContentScrollView() {
        assertCoreSnapshot("HeaderFooterContentScrollView") {
            HeaderFooterContentScrollView(model: HeaderFooterScrollModel()) {
                HStack {
                    Image(systemName: "chevron.left")
                    Spacer()
                    Text("Apple Store")
                }
                .padding()
            } content: {
                Form {
                    ForEach(1...12, id: \.self) { index in
                        Text("Adventure row \(index)")
                    }
                }
            } footer: {
                Label("Mage", systemImage: "gear")
                    .frame(maxWidth: .infinity)
                    .padding()
            } background: {
                Rectangle().fill(Color.orange.gradient)
            }
        }
    }

    // snapshot-root: CoreRPG::NameItemNewRow
    @Test("NameItemNewRow")
    func nameItemNewRow() {
        assertCoreSnapshot("NameItemNewRow") {
            NameItemNewRow(
                itemId: .fixture1,
                name: "**Super cool Name** cool and more **cool**",
                cacheItemListModel: CacheItemListModel(),
                listDisplayModel: ListDisplayModel(),
                searchModel: SearchModel.preview(search: "cool")
            )
            .padding()
        }
    }

    // snapshot-root: CoreRPG::LinkHighlightTextView
    @Test("LinkHighlightTextView")
    func linkHighlightTextView() {
        let text = "**Mega** nice with a [map link](RPG://MAPS/0/00000000-0000-0000-0000-000000000001)."
        let model = LinkHighlightTextModel(
            linkControllable: FakeLinkController.fake,
            text: text,
            highlightedText: "in"
        )

        assertCoreSnapshot("LinkHighlightTextView") {
            LinkHighlightTextView(model: model)
                .frame(width: 300)
                .padding()
        }
    }

    // snapshot-root: CoreRPG::SheetEntryView
    @Test("SheetEntryView")
    func sheetEntryView() {
        @FocusState var focusedEntryId: UUID?
        
        assertCoreSnapshot("SheetEntryView") {
            CoreRPGNamespaceSnapshotHarness { namespace in
                SheetEntryView(
                    rootModel: .fake,
                    parentModel: .empty,
                    entryModel: .empty,
                    isEditor: true,
                    linkTypes: EmptyLinkTransferable.self,
                    focusedEntryId: $focusedEntryId
                )
            }
            .environment(AppGameStateModel())
        }
    }

    // snapshot-root: CoreRPG::SheetView
    @Test("SheetView")
    func sheetView() {
        @FocusState var focusedEntryId: UUID?
        
        assertCoreSnapshot("SheetView") {
            CoreRPGNamespaceSnapshotHarness { namespace in
                SheetView(
                    root: ItemRootController.fake,
                    rootModel: .fake,
                    sheetModel: .empty,
                    isEditor: true,
                    linkTypes: EmptyLinkTransferable.self,
                    focusedEntryId: $focusedEntryId
                )
            }
            .environment(AppGameStateModel())
        }
    }

    // snapshot-root: CoreRPG::SheetRootView
    @Test("Structured sheet review collapsed")
    func structuredSheetReviewCollapsed() {
        let fixture = structuredSheetReviewFixture(
            existingEntries: [
                FakeEntryModel(id: .fixture2, name: "Ancient Door", content: "Sealed by old runes")
            ],
            importedEntries: [
                FakeEntryModel(id: .fixture2, name: "Ancient Door", content: "The runes have faded")
            ],
            mergedEntries: [
                FakeEntryModel(id: .fixture2, name: "Ancient Door", content: "Sealed, but the runes are fading")
            ],
            decision: .merge
        )

        assertCoreSnapshot("StructuredSheetReviewCollapsed") {
            structuredSheetRootView(fixture)
        }
    }

    // Expanded structured sheet-review state.
    @Test("Structured sheet review expanded with New selected")
    func structuredSheetReviewExpandedSelectedNew() {
        let fixture = structuredSheetReviewFixture(
            existingEntries: [
                FakeEntryModel(id: .fixture2, name: "Ancient Door", content: "Sealed by old runes")
            ],
            importedEntries: [
                FakeEntryModel(id: .fixture2, name: "Open Archway", content: "The runes have vanished")
            ],
            mergedEntries: [
                FakeEntryModel(id: .fixture2, name: "Ancient Door", content: "Sealed, but the runes are fading")
            ],
            decision: .imported,
            isExpanded: true
        )

        assertCoreSnapshot("StructuredSheetReviewExpandedSelectedNew") {
            structuredSheetRootView(fixture)
        }
    }

    // Structured sheet-review placeholder state.
    @Test("Structured sheet review absent version")
    func structuredSheetReviewAbsentVersion() {
        let fixture = structuredSheetReviewFixture(
            existingEntries: [
                FakeEntryModel(id: .fixture2, name: "Removed Passage", content: "Only in the existing adventure")
            ],
            importedEntries: [],
            mergedEntries: [],
            decision: .imported,
            isExpanded: true
        )

        assertCoreSnapshot("StructuredSheetReviewAbsentVersion") {
            structuredSheetRootView(fixture)
        }
    }

    // Unchanged structured sheet entry.
    @Test("Structured sheet review unchanged entry")
    func structuredSheetReviewUnchangedEntry() {
        let unchanged = FakeEntryModel(
            id: .fixture2,
            name: "Unchanged Hall",
            content: "No version control is needed for this row"
        )
        let fixture = structuredSheetReviewFixture(
            existingEntries: [unchanged],
            importedEntries: [unchanged],
            mergedEntries: [unchanged],
            decision: .merge
        )

        assertCoreSnapshot("StructuredSheetReviewUnchangedEntry") {
            structuredSheetRootView(fixture)
        }
    }

    // snapshot-root: CoreRPG::ImportReviewSheetDetailView
    @Test("Structured import detail keeps reference diagnostics")
    func structuredImportReviewDetail() {
        let fixture = FakeItemRootControllerFixture()
        let reviewItem = makeStructuredReviewItem(
            existingEntries: [
                FakeEntryModel(id: .fixture2, name: "Old Gate", content: "Closed")
            ],
            importedEntries: [
                FakeEntryModel(id: .fixture2, name: "New Gate", content: "Open")
            ],
            mergedEntries: [
                FakeEntryModel(id: .fixture2, name: "Gate", content: "Partly open")
            ],
            decision: .merge
        )
        reviewItem.itemModel.references = [
            SingleReviewReference(
                itemName: "Missing Chronicle",
                destination: ItemRowModel(itemId: .fixture5, typeId: .adventure),
                status: .missing
            )
        ]
        let reviewModel = ImportReviewModel(modules: [
            ImportReviewModule(id: .adventure, reviewItems: [reviewItem])
        ])

        assertCoreSnapshot("StructuredImportReviewDetail") {
            ImportReviewSheetDetailView(
                item: reviewItem,
                root: fixture.root,
                rootManager: RootManager.preview(fake: fixture.root),
                reviewModel: reviewModel
            )
        }
    }

    // snapshot-root: CoreRPG::DisclosureGroupTV
    @Test("DisclosureGroupTV")
    func disclosureGroupTV() {
        assertCoreSnapshot("DisclosureGroupTV") {
            DisclosureGroupTV(isExpanded: .constant(true)) {
                Text("The party has entered the dungeon.")
            } label: {
                Label("Adventure notes", systemImage: "book.closed")
            }
            .padding()
        }
    }

#if os(iOS)
    // snapshot-root: CoreRPG::HideKeyboardFocusView
    @Test("HideKeyboardFocusView")
    func hideKeyboardFocusView() {
        assertCoreSnapshot("HideKeyboardFocusView") {
            CoreRPGFocusSnapshotHarness(Int.self) { focus in
                HideKeyboardFocusView(enabled: true, focusedField: focus)
                    .padding()
            }
        }
    }
#endif

    private func structuredSheetReviewFixture(
        existingEntries: [FakeEntryModel],
        importedEntries: [FakeEntryModel],
        mergedEntries: [FakeEntryModel],
        decision: SingleReviewDecision,
        isExpanded: Bool = false
    ) -> StructuredSheetReviewFixture {
        let reviewItem = makeStructuredReviewItem(
            existingEntries: existingEntries,
            importedEntries: importedEntries,
            mergedEntries: mergedEntries,
            decision: decision
        )
        let currentSheet = structuredSheet(for: reviewItem.itemModel.materializedItem())
        let versionSheets = Dictionary(
            uniqueKeysWithValues: SingleReviewDecision.allCases.map { versionDecision in
                (
                    versionDecision,
                    structuredSheet(for: reviewItem.itemModel.materializedItem(for: versionDecision))
                )
            }
        )
        SheetReviewTreeBuilder.decorate(
            sheetModel: currentSheet,
            reviewItem: reviewItem,
            versionSheets: versionSheets
        )
        currentSheet.entries.compactMap(\.entryReviewModel).first?.isExpanded = isExpanded

        let controllerFixture = FakeItemRootControllerFixture()
        let rootManager = RootManager.preview(fake: controllerFixture.root)
        let rootModel = SheetRootModel(
            rootManager: rootManager,
            linkControllable: controllerFixture.linkController,
            sheetControllable: controllerFixture.sheetController,
            sheetModel: currentSheet,
            isEditor: false
        )
        return StructuredSheetReviewFixture(root: controllerFixture.root, rootModel: rootModel)
    }

    private func makeStructuredReviewItem(
        existingEntries: [FakeEntryModel],
        importedEntries: [FakeEntryModel],
        mergedEntries: [FakeEntryModel],
        decision: SingleReviewDecision
    ) -> ImportReviewItemModel {
        let existing = FakeItemModel(
            id: .fixture1,
            name: "Existing Adventure",
            description: "Current library version",
            entries: existingEntries
        )
        let imported = FakeItemModel(
            id: .fixture1,
            name: "Imported Adventure",
            description: "Incoming file version",
            entries: importedEntries
        )
        let merged = FakeItemModel(
            id: .fixture1,
            name: "Merged Adventure",
            description: "Combined review version",
            entries: mergedEntries
        )
        let itemModel = SingleItemImportModel.from(
            item: SingleReviewItem(existing: existing, imported: imported, merged: merged)
        )
        itemModel.applyItemDecision(decision)
        return ImportReviewItemModel(
            id: .fixture1,
            kind: .different,
            existingStatus: existing.name,
            importedStatus: imported.name,
            mergedStatus: merged.name,
            itemModel: itemModel
        )
    }

    private func structuredSheet(for item: any ItemDataAccessible) -> SheetModel {
        SheetModel(
            source: ItemRowModel(itemId: item.id, typeId: .adventure),
            name: item.name,
            description: item.description,
            entries: item.entries.map { entry in
                SheetModel(
                    source: ItemRowModel(itemId: item.id, entryId: entry.id, typeId: .adventure),
                    name: entry.name,
                    description: entry.content,
                    entries: []
                )
            }
        )
    }

    private func structuredSheetRootView(_ fixture: StructuredSheetReviewFixture) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                SheetRootView(
                    root: fixture.root,
                    rootModel: fixture.rootModel,
                    linkTypes: EmptyLinkTransferable.self
                )
            }
            .padding()
        }
    }

    private func assertCoreSnapshot<Content: View>(
        _ name: String,
        @ViewBuilder content: () -> Content
    ) {
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
                .environment(OptionKeyDownModel())
                .environment(GroupItemSelectionModel())
                .environment(ItemRootController.previewFixture())
                .cloudKitAccountChecksEnabled(false)
                .itemStateRestorationEnabled(false)
                .meshAnimationEnabled(false)
                .deterministicSnapshotEnvironment()
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

@MainActor
private struct StructuredSheetReviewFixture {
    let root: ItemRootController
    let rootModel: SheetRootModel
}
