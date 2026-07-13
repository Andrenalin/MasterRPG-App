// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Supporting Types

struct EditingItem: Identifiable {
    let id: UUID
    let model: any ItemDataAccessable

    init(_ model: any ItemDataAccessable) {
        self.id = model.id
        self.model = model
    }
}

// MARK: - Main View

public struct ItemDetailRootView<Editor: View, LinkTypes: LinkDataTransferable>: View {

    /// Configuration for ItemDetailRootView behavior
    public struct Configuration {
        public var editorAsBackground: Bool
        public var disableHideHeader: Bool
        public var isSubFolder: Bool

        public init(
            editorAsBackground: Bool = false,
            disableHideHeader: Bool = false,
            isSubFolder: Bool = false
        ) {
            self.editorAsBackground = editorAsBackground
            self.disableHideHeader = disableHideHeader
            self.isSubFolder = isSubFolder
        }
    }

    public init(
        root: any ItemRootControllable,
        detailListController: FolderListControllable,
        selectedModel: any ItemDataAccessable,
        configuration: Configuration = Configuration(),
        linkTypes: LinkTypes.Type,
        @ViewBuilder editor: () -> Editor
    ) {
        self.root = root
        self.folderListController = detailListController
        self.selectedModel = selectedModel
        self.configuration = configuration
        self.editor = editor()
    }

    let root: any ItemRootControllable
    let folderListController: FolderListControllable
    let selectedModel: any ItemDataAccessable
    let configuration: Configuration
    let editor: Editor
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var editingItem: EditingItem?
    @State private var itemIdHasUrl = UUID()
    @State private var headerModel = HeaderScrollModel()
    @Namespace private var editSheetNamespace
    
    @Environment(AppWindowSizeModel.self) private var appSizeModel
    @Environment(\.navigator) private var navigator
    
    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        ItemDetailContentView(
            root: root,
            model: selectedModel,
            configuration: configuration,
            editor: editor,
            headerModel: headerModel,
            folderListController: folderListController,
            editingItem: $editingItem,
            editSheetNamespace: editSheetNamespace
        )
        .tint(root.configurable.module.tint)
        .onChange(of: selectedModel.id, initial: true) {
            handleModelIdChange()
        }
        .task(id: selectedModel.id) {
            await openEditorForNewItemIfNeeded()
        }
        .onChange(of: selectedModel.name) {
            handleModelNameChange()
        }
        .onChange(of: selectedModel.url) { oldValue, _ in
            handleModelUrlChange(oldValue: oldValue)
        }
        .onChange(of: root.navigationModel.openHeaderEditor) {
            guard root.navigationModel.openHeaderEditor else { return }
            root.navigationModel.openHeaderEditor = false
            openEditingSheet()
        }
        .onChange(of: folderListController.listModel.detailListModel?.subFolderRoute) {
            guard let itemId = folderListController.listModel.detailListModel?.subFolderRoute else { return }
            if appSizeModel.mode == .compact {
                navigator.navigate(to: folderListController.folderDestination(for: itemId))
                folderListController.listModel.detailListModel?.subFolderRoute = nil
            }
        }
        .sheet(item: $editingItem) { item in
            ManagedPresentationView {
                editingSheet(model: item.model)
            }
        }
    }
}

// MARK: - Computed Properties

private extension ItemDetailRootView {
    var fileTypes: [UTType] {
        root.editControllable.fileUrlDataController?.fileTypes ?? []
    }
    
    var shouldShowContent: Bool {
        selectedModel.url != nil || fileTypes.isEmpty || selectedModel.specialCategory
    }
}

// MARK: - State Handlers

private extension ItemDetailRootView {
    func openEditingSheet() {
        withAnimation(.easeInOut) { 
            editingItem = EditingItem(selectedModel) 
        }
    }
    
    func openEditorForNewItemIfNeeded() async {
        await Task.yield()
        guard selectedModel.name.isEmpty && shouldShowContent else { return }
        openEditingSheet()
    }

    func handleModelIdChange() {
        editingItem = nil
        folderListController.resetDetail(model: selectedModel)
        
        itemIdHasUrl = if selectedModel.url != nil {
            selectedModel.id
        } else if shouldShowContent {
            selectedModel.id
        } else {
            UUID()
        }
    }

    func handleModelNameChange() {
        guard selectedModel.name.isEmpty && shouldShowContent else { return }
        openEditingSheet()
    }

    func handleModelUrlChange(oldValue: URL?) {
        guard oldValue == nil, itemIdHasUrl != selectedModel.id else { return }
        openEditingSheet()
    }
}

// MARK: - Presentation Views

private extension ItemDetailRootView {
    func editingSheet(model: any ItemDataAccessable) -> some View {
        ItemHeaderEditorView(editControllable: root.editControllable, model: model)
            .colorScheme(colorScheme)
            .preferredColorScheme(colorScheme)
            .presentationContentInteraction(.resizes)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled)
            .tint(root.configurable.module.tint)
#if os(iOS)
            .navigationTransition(.zoom(sourceID: "edit", in: editSheetNamespace))
#endif
    }
}

// MARK: - Content View (Extracted)

private struct ItemDetailContentView<Editor: View, LinkTypes: LinkDataTransferable>: View {
    let root: any ItemRootControllable
    let model: any ItemDataAccessable
    let configuration: ItemDetailRootView<Editor, LinkTypes>.Configuration
    let editor: Editor
    let headerModel: HeaderScrollModel
    let folderListController: FolderListControllable
    @Binding var editingItem: EditingItem?
    let editSheetNamespace: Namespace.ID
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        HeaderContentScrollView(
            model: headerModel,
            backgroundColor: root.configurable.module.color,
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
        .overlay(alignment: .center) {
            entryEditor
        }
        .animation(.easeInOut, value: model.url)
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
                    editSheetNamespace: editSheetNamespace,
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
                        withAnimation { folderListController.listModel.detailListModel?.subFolderRoute = nil }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .padding(8)
                    .glassEffectAll()
                    .padding(.trailing, 8)
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
    
    private var fileTypes: [UTType] {
        root.editControllable.fileUrlDataController?.fileTypes ?? []
    }
    
    private var shouldShowContent: Bool {
        model.url != nil || fileTypes.isEmpty || model.specialCategory
    }
    
    private func openEditingSheet() {
        withAnimation(.easeInOut) { 
            editingItem = EditingItem(model) 
        }
    }
}

// MARK: - Header View (Extracted)

private struct ItemDetailHeaderView: View {
    let module: NetworkModules
    let model: any ItemDataAccessable
    let cacheItemListModel: CacheItemListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ItemDetailOverlayView(
                model: model,
                cacheItemListModel: cacheItemListModel,
                listDisplayModel: listDisplayModel,
                searchModel: searchModel
            )
            .padding()
        }
        .overlay(alignment: .top) {
            navigationHeader
                .font(.title)
                .padding(.top, -64)
        }
    }
    
    private var navigationHeader: Text {
        Text("\(Image(systemName: module.icon)) \(module.title)")
    }
}

// MARK: - File Importer View (Extracted & Unified)

private struct ItemFileImporterView: View {
    let root: any ItemRootControllable
    let model: any ItemDataAccessable
    let fileTypes: [UTType]
    let isInitial: Bool
    
    var body: some View {
        Group {
            if isInitial {
                initialStyle
            } else {
                overlayStyle
            }
        }
    }
    
    @ViewBuilder
    private var initialStyle: some View {
        HStack {
            fileImporterContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .opacity(1)
        .transition(.scale)
    }
    
    @ViewBuilder
    private var overlayStyle: some View {
        HStack(alignment: .bottom, spacing: 0) {
            filePathDisplay
            Spacer(minLength: 20)
            fileImporterContent
                .zIndex(5)
        }
    }
    
    @ViewBuilder
    private var fileImporterContent: some View {
        if root.viewControllable.fileImporterViewType == .file {
            FileImporterView(
                editControllable: root.editControllable,
                fileTypes: fileTypes,
                itemId: model.id
            )
            .applyIf(isInitial) {
                $0.padding(32)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(.tint, lineWidth: 2)
                    }
            }
        } else {
            root.viewControllable.fileImporterView(
                for: model.id,
                preopen: isInitial,
                layoutDown: !isInitial
            )
        }
    }
    
    @ViewBuilder
    private var filePathDisplay: some View {
        if !isInitial {
            HStack {
                Text(model.url?.path(percentEncoded: false) ?? 
                     String(localized: "No file is set", bundle: .module).localizedString)
                    .font(.callout)
            }
            .padding(6)
#if !os(visionOS)
            .glassEffectAll(.regular.interactive())
#endif
        }
    }
}

// MARK: - Editor Foreground View (Extracted)

private struct ItemEditorForegroundView<Editor: View>: View {
    let editor: Editor
    let model: any ItemDataAccessable
    let root: any ItemRootControllable
    let folderListController: FolderListControllable
    let shouldShowContent: Bool
    let isSubFolder: Bool

    @State private var scrollPosition = ScrollPosition(idType: UUID.self)
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        Group {
            if model.specialCategory {
                specialCategoryContent
            } else {
                formEditorContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .opacity(shouldShowContent ? 1 : 0)
        .transition(.scale)
    }
    
    @ViewBuilder
    private var specialCategoryContent: some View {
        ItemDetailOverlayView(
            model: model,
            cacheItemListModel: root.editControllable.cacheItemListModel,
            listDisplayModel: folderListController.listDisplayModel,
            searchModel: folderListController.searchModel,
            fullHeader: false,
            onlyDescription: true
        )
        .padding()
        
        ListRootView(
            root: root,
            listController: folderListController,
            parentModel: model,
            isSubFolder: isSubFolder
        )
        //.environment(folderListController.listDisplayModel)
    }
    
    private var formEditorContent: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if !model.description.isEmpty {
                    ItemDetailOverlayView(
                        model: model,
                        cacheItemListModel: root.editControllable.cacheItemListModel,
                        listDisplayModel: folderListController.listDisplayModel,
                        searchModel: folderListController.searchModel,
                        fullHeader: false,
                        onlyDescription: true
                    )
                }

                editor
            }
            .scrollTargetLayout()
            .padding()
        }
        .scrollPosition($scrollPosition, anchor: .center)
        .scrollClipDisabled(true)
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: root.editControllable.editorModel.sheetEditorModel.scrollEntryId) { _, entryID in
            guard let entryID else { return }
            withAnimation(.smooth) {
                scrollPosition.scrollTo(id: entryID, anchor: .center)
            }
            root.editControllable.editorModel.sheetEditorModel.scrollEntryId = nil
        }
    }
}

// MARK: - Editor Background View (Extracted)

private struct ItemEditorBackgroundView<Editor: View>: View {
    let editor: Editor
    let model: any ItemDataAccessable
    let root: any ItemRootControllable
    let folderListController: FolderListControllable
    let fileTypes: [UTType]
    let shouldShowContent: Bool
    
    var body: some View {
        editor
            .id(model.id)
            .overlay(alignment: .bottom) {
                if !model.description.isEmpty {
                    GlassEffectContainerAll {
                        ItemDetailOverlayView(
                            model: model,
                            cacheItemListModel: root.editControllable.cacheItemListModel,
                            listDisplayModel: folderListController.listDisplayModel,
                            searchModel: folderListController.searchModel,
                            fullHeader: false,
                            onlyDescription: true,
                            lines: 3
                        )
                        .padding(.horizontal, 8)
                        .padding(6)
#if !os(visionOS)
                        .glassEffectAll(.regular)
#endif
                    }
                    .padding()
                }
            }
            .overlay(alignment: .top) {
                if !model.specialCategory {
                    GlassEffectContainerAll {
                        ItemFileImporterView(
                            root: root,
                            model: model,
                            fileTypes: fileTypes,
                            isInitial: false
                        )
                        .zIndex(10)
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .opacity(shouldShowContent ? 1 : 0)
            .transition(.opacity)
    }
}

private struct ItemDetailPreview: View {
    private let root = ItemRootController.fake
    private let model = FakeItemModel.empty

    var body: some View {
        ItemDetailRootView(
            root: root,
            detailListController: FakeFolderListController.fake,
            selectedModel: model,
            linkTypes: EmptyLinkTransferable.self
        ) {
            Text("Editor content")
        }
    }
}

#Preview("Item Detail") {
    ItemDetailPreview()
}

#Preview("Item Detail Header") {
    ItemDetailHeaderView(
        module: .none,
        model: FakeItemModel.empty,
        cacheItemListModel: CacheItemListModel(),
        listDisplayModel: ListDisplayModel(),
        searchModel: FakeSearchController.fake.searchModel
    )
    .padding()
}

#Preview("File Importer") {
    ItemFileImporterView(root: ItemRootController.fake, model: FakeItemModel.empty, fileTypes: [], isInitial: true)
}

#Preview("Foreground Editor") {
    ItemEditorForegroundView(
        editor: Text("Editor content"),
        model: FakeItemModel.empty,
        root: ItemRootController.fake,
        folderListController: FakeFolderListController.fake,
        shouldShowContent: true,
        isSubFolder: false
    )
}

#Preview("Background Editor") {
    ItemEditorBackgroundView(
        editor: Color.blue.opacity(0.2),
        model: FakeItemModel.empty,
        root: ItemRootController.fake,
        folderListController: FakeFolderListController.fake,
        fileTypes: [],
        shouldShowContent: true
    )
}

#Preview("Item Detail Root Direct") {
    ItemDetailRootView(
        root: ItemRootController.fake,
        detailListController: FakeFolderListController.fake,
        selectedModel: FakeItemModel.empty,
        linkTypes: EmptyLinkTransferable.self
    ) {
        Text("Editor content")
    }
}

#Preview("Item Detail Content Direct") {
    @Previewable @Namespace var namespace
    ItemDetailContentView<Text, EmptyLinkTransferable>(
        root: ItemRootController.fake,
        model: FakeItemModel.empty,
        configuration: .init(),
        editor: Text("Editor content"),
        headerModel: HeaderScrollModel(),
        folderListController: FakeFolderListController.fake,
        editingItem: .constant(nil),
        editSheetNamespace: namespace
    )
}

// MARK: - Toolbar Content (Extracted)

private struct ItemDetailToolbarContent: ToolbarContent {
    let root: any ItemRootControllable
    let model: any ItemDataAccessable
    let shouldShowContent: Bool
    let editSheetNamespace: Namespace.ID
    let onEdit: () -> Void
    
    var body: some ToolbarContent {
        if !root.openFileWindowModel.showItem {
            ToolbarItem(placement: .primaryAction) {
                if shouldShowContent {
                    Button(action: onEdit) {
                        Label {
                            Text("Edit", bundle: .module)
                        } icon: {
                            Image(systemName: "pencil")
                        }
                        .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel(Text("Edit Item", bundle: .module))
                    .accessibilityHint(Text("Edit item details", bundle: .module))
                }
            }
#if os(iOS)
            .matchedTransitionSource(id: "edit", in: editSheetNamespace)
#endif
            
            ToolbarItemGroup(placement: .secondaryActionAll) {
                MenuUndoRedoButton(root: root)
            }
        }
    }
}

// MARK: - View Extensions

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
