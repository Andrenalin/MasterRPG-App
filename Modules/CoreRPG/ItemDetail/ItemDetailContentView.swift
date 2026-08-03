// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

struct ItemDetailContentView<Editor: View, LinkTypes: LinkDataTransferable>: View {
    let root: any ItemRootControllable
    let model: any ItemDataAccessable
    let configuration: ItemDetailRootView<Editor, LinkTypes>.Configuration
    let editor: Editor
    let headerModel: HeaderScrollModel
    let folderListController: FolderListControllable
    @Binding var editingItem: EditingItem?

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        HeaderContentScrollView(
            model: headerModel,
            backgroundColor: theme.background(for: root.configurable.module),
            disableHideHeader: configuration.disableHideHeader || configuration.isSubFolder
        ) {
            ItemDetailHeaderView(
                module: root.configurable.module,
                model: model,
                cacheItemListModel: root.editControllable.cacheItemListModel,
                listDisplayModel: folderListController.listDisplayModel,
                searchModel: folderListController.searchModel
            )
        } content: {
            contentBody
                .overlay {
                    subFolderDetail
                }
        }
        .allowsHitTesting(!isEntryEditorPresented && editingItem == nil)
        .accessibilityHidden(isEntryEditorPresented || editingItem != nil)
        .overlay(alignment: .center) {
            entryEditor
        }
        .overlay(alignment: .center) {
            itemHeaderEditor
        }
        .animation(accessibilityReduceMotion ? nil : .easeInOut, value: model.url)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .applyFileDropIfNeeded(model: model, fileTypes: fileTypes, root: root)
        .modifier(OpenFileViewerViewModifier(
            model: model,
            openFileWindowModel: root.openFileWindowModel,
            module: root.configurable.module
        ))
        .toolbar {
            if !configuration.isSubFolder {
                ItemDetailToolbarContent(
                    root: root,
                    model: model,
                    shouldShowContent: shouldShowContent,
                    onEdit: { openEditingSheet() }
                )
            }
        }
    }
    
    @ViewBuilder private var subFolderDetail: some View {
        if let itemId = folderListController.listModel.detailListModel?.subFolderRoute {
            folderListController.folderInlineDestination(for: itemId).asAnyView()
                .overlay(alignment: .topTrailing) {
                    Button {
                        withAnimation(accessibilityReduceMotion ? nil : .default) {
                            folderListController.listModel.detailListModel?.subFolderRoute = nil
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .padding(8)
                    .glassEffectAll()
                    .padding(.trailing, 8)
                    .accessibilityLabel(Text("Close", bundle: .module))
                }
                .background {
                    Rectangle().fill(Color.adaptiveBackground)
                }
                .transition(.move(edge: .bottom))
        }
    }
    
    @ViewBuilder
    private var contentBody: some View {
        ZStack {
            if !shouldShowContent {
                ItemFileImporterView(
                    root: root,
                    model: model,
                    fileTypes: fileTypes,
                    isInitial: true
                )
            }
            
            if configuration.editorAsBackground && !model.specialCategory {
                ItemEditorBackgroundView(
                    editor: editor,
                    model: model,
                    root: root,
                    folderListController: folderListController,
                    fileTypes: fileTypes,
                    shouldShowContent: shouldShowContent
                )
            } else {
                ItemEditorForegroundView(
                    editor: editor,
                    model: model,
                    root: root,
                    folderListController: folderListController,
                    shouldShowContent: shouldShowContent,
                    isSubFolder: configuration.isSubFolder
                )
            }
        }
    }
    
    @ViewBuilder
    private var entryEditor: some View {
        if root.editControllable as? (any EntryDataEditable) != nil, let rootManager = root.rootManager {
            EntryEditorView(
                rootManager: rootManager,
                editorModel: root.editControllable.editorModel.sheetEditorModel,
                linkTypes: LinkTypes.self
            )
        }
    }

    @ViewBuilder
    private var itemHeaderEditor: some View {
        if let editingItem {
            ItemHeaderEditorView(
                editControllable: root.editControllable,
                model: editingItem.model,
                module: root.configurable.module,
                dismiss: { self.editingItem = nil }
            )
            .id(editingItem.id)
            .transition(itemHeaderEditorTransition)
            .animation(accessibilityReduceMotion ? nil : .bouncy, value: editingItem.id)
        }
    }

    // AppKit doesn't reliably redraw the NSTextView backing a TextEditor when it's caught in
    // a SwiftUI scale-transform transition on macOS: the text can stay blank or mis-sized until
    // something else (e.g. a window resize) forces a relayout. A plain fade avoids the transform.
    private var itemHeaderEditorTransition: AnyTransition {
#if os(macOS)
        .opacity
#else
        .scale
#endif
    }

    private var fileTypes: [UTType] {
        root.editControllable.fileUrlDataController?.fileTypes ?? []
    }
    
    private var shouldShowContent: Bool {
        model.url != nil || fileTypes.isEmpty || model.specialCategory
    }

    private var isEntryEditorPresented: Bool {
        guard let editController = root.editControllable as? any EntryDataEditable else {
            return false
        }
        let editorModel = editController.editorModel.sheetEditorModel
        return editorModel.itemId != nil &&
            editorModel.entryId != nil &&
            !editController.editorModel.deactivateEntryEditor
    }
    
    private func openEditingSheet() {
        withAnimation(accessibilityReduceMotion ? nil : .easeInOut) {
            editingItem = EditingItem(model) 
        }
    }
}

private extension View {
    @ViewBuilder
    func applyFileDropIfNeeded(
        model: any ItemDataAccessable,
        fileTypes: [UTType],
        root: any ItemRootControllable
    ) -> some View {
#if !os(tvOS)
        if model.category != .folder && !fileTypes.isEmpty {
            self.onDrop(of: [.fileURL], delegate: FileDropDelegate(
                for: fileTypes,
                updateFile: { url in
                    Task {
                        await root.editControllable.resetFile(url: url, itemId: model.id)
                    }
                }
            ))
        } else {
            self
        }
#else
        self
#endif
    }
}

#Preview("Item Detail Content Direct") {
    let fixture = FakeItemRootControllerFixture()
    ItemDetailContentView<Text, EmptyLinkTransferable>(
        root: fixture.root,
        model: FakeItemModel.empty,
        configuration: .init(),
        editor: Text(verbatim: "Editor content"),
        headerModel: HeaderScrollModel(),
        folderListController: fixture.folderListController,
        editingItem: .constant(nil)
    )
}
