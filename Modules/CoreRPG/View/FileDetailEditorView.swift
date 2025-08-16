// @copyright André Trettin

import CoreExternalRPG
import SwiftUI
import UniformTypeIdentifiers

public struct FileDetailEditorView<EditController: EditControllable, Route: NavigationDestination, Importer: View, Inside: View, Editor: View, Row: View, Bottom: View, Inspector: View>: View where EditController.Model.ID == UUID {
    public init(model: EditController.Model, editController: EditController, menuController: any ItemListContextMenuControllable, fileTypes: [UTType], route: @escaping (UUID) -> Route, @ViewBuilder importer: () -> Importer, @ViewBuilder background: () -> Inside, @ViewBuilder editor: () -> Editor = EmptyView.init, @ViewBuilder row: @escaping (UUID) -> Row, @ViewBuilder bottom: () -> Bottom = EmptyView.init, @ViewBuilder inspector: () -> Inspector = EmptyView.init) {
        self.model = model
        self.editController = editController
        self.menuController = menuController
        self.fileTypes = fileTypes
        self.route = route
        self.importer = importer()
        self.background = background()
        self.editor = editor()
        self.row = row
        self.bottom = bottom()
        self.inspector = inspector()
        self.cacheItemListModel = CacheItemListModel()
    }

    let model: EditController.Model
    let editController: EditController
    let menuController: ItemListContextMenuControllable
    let fileTypes: [UTType]
    let route: (UUID) -> Route
    let importer: Importer
    let background: Inside
    let editor: Editor
    let row: (UUID) -> Row
    let bottom: Bottom
    let inspector: Inspector
    let cacheItemListModel: CacheItemListModel

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    @State private var isEditing = false
    @State private var showInspector = false
    @State private var itemIdHasUrl: EditController.Model.ID = UUID()

    @Environment(ListModel.self) private var listModel
    @Environment(SearchModel.self) private var searchModel
    @Environment(GroupItemSelectionModel.self) private var selection
    @Environment(OpenFileWindowModel.self) private var openFileWindowModel

    public var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            initialFileImporterView

            VStack {
                backgroundView

                contentView

                bottomView
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .animation(.default, value: model.url)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.id, initial: true) {
            openFileWindowModel.itemId = model.id
            openFileWindowModel.url = model.url
            guard model.url != nil else {
                itemIdHasUrl = hasFile ? model.id : UUID()
                return
            }
            itemIdHasUrl = model.id
        }
        .onChange(of: model.name, initial: true) {
            guard model.name.isEmpty && (hasFile || model.specialCategory) else { return }
            withAnimation { isEditing = true }
        }
        .onChange(of: model.url) { oldValue, newValue in
            guard oldValue == nil else { return }
            guard itemIdHasUrl != model.id else { return }
            withAnimation { isEditing = true }
        }
        .onChange(of: selection.selectedItem) {
            openFileWindowModel.itemId = selection.selectedItem ?? model.id
        }
#if !os(tvOS)
        .applyIf(model.category != .folder && !fileTypes.isEmpty) {
            $0.onDrop(of: [.fileURL], delegate: FileDropDelegate(for: fileTypes, updateFile: updateFile))
        }
#endif
        .inspector(isPresented: $showInspector) {
            if model.specialCategory {
                inspector
            }
        }
        .sheet(isPresented: $isEditing) {
            DetailItemEditorView(model: model, editController: editController, name: \.name, category: \.category, tags: \.tags, description: \.information)
            
                .presentationContentInteraction(.resizes)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if openFileWindowModel.showItem == false && (hasFile || model.specialCategory) {
                    Button {
                        withAnimation { isEditing = true }
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                if horizontalSizeClass == .regular && model.specialCategory {
                    Button {
                        withAnimation { showInspector.toggle() }
                    } label: {
                        Image(systemName: "scope")
                    }
                }
            }
        }
    }
}

private extension FileDetailEditorView {
    var hasFile: Bool {
        model.url != nil || fileTypes.isEmpty
    }
    
    @ViewBuilder
    var backgroundView: some View {
        background
    }

    @ViewBuilder
    var initialFileImporterView: some View {
        HStack {
            importer
                .padding(32)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .opacity(hasFile || model.specialCategory ? 0 : 1)
        .transition(.scale)
    }

    @ViewBuilder
    var bottomView: some View {
        if hasFile && model.specialCategory == false {
            CarouselItemView(model: model, editController: editController, selection: selection) {
                bottom
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
            .environment(selection)
            .transition(.move(edge: .bottom))
        }
    }

    @ViewBuilder
    var contentView: some View {
        VStack(spacing: 8) {
            DetailOverlayView(itemId: model.id, model: model, nameKeyPath: \.name, categoryKeyPath: \.category, tagsKeyPath: \.tags, descriptionKeyPath: \.information)

            editor
            
            if model.specialCategory {
                ItemListView(editController: editController, menuController: menuController, listModel: listModel.lastSubListModel(for: model.id, parentIsFolder: model.category == .folder), parentModel: model, items: model.subItems.0, module: EditController.Model.typeId) { id in
                    route(id)
                } row: { itemId in
                    row(itemId)
                }
            }
        }
        .padding()
        .opacity(hasFile || model.specialCategory ? 1 : 0)
        .transition(.scale)
    }

    private func updateFile(url: URL) {
        editController.resetFile(url: url, in: model)
    }
}
