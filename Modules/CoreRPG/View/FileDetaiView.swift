// @copyright André Trettin

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

public struct FileDetailEditorView<Model: Identifiable, EditController: EditControllable, Importer: View, Inside: View, Editor: View>: View where Model.ID == UUID, Model == EditController.Model {
    public init(model: Model, editController: EditController, nameKeyPath: KeyPath<Model, String>, categoryKeyPath: KeyPath<Model, ItemListCategory>, tagsKeyPath: KeyPath<Model, [String]>, descriptionKeyPath: KeyPath<Model, String>, urlKeypath: KeyPath<Model, URL?>, fileTypes: [UTType], @ViewBuilder importer: () -> Importer, @ViewBuilder inside: () -> Inside = EmptyView.init, @ViewBuilder editor: () -> Editor = EmptyView.init) {
        self.model = model
        self.editController = editController
        self.nameKeyPath = nameKeyPath
        self.categoryKeyPath = categoryKeyPath
        self.tagsKeyPath = tagsKeyPath
        self.descriptionKeyPath = descriptionKeyPath
        self.urlKeyPath = urlKeypath
        self.fileTypes = fileTypes
        self.importer = importer()
        self.inside = inside()
        self.editor = editor()
        self.cacheItemListModel = CacheItemListModel()
    }
    
    let model: Model
    let editController: EditController
    let nameKeyPath: KeyPath<Model, String>
    let categoryKeyPath: KeyPath<Model, ItemListCategory>
    let tagsKeyPath: KeyPath<Model, [String]>
    let descriptionKeyPath: KeyPath<Model, String>
    let urlKeyPath: KeyPath<Model, URL?>
    let fileTypes: [UTType]
    let importer: Importer
    let inside: Inside
    let editor: Editor
    let cacheItemListModel: CacheItemListModel

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    @State private var isEditing = false
    @State private var itemIdHasUrl: Model.ID = UUID()

    
    public var body: some View {
        ZStack(alignment: .top) {
            initialFileImporterView
            
            contentView
        }
        .animation(.default, value: model[keyPath: urlKeyPath])
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.id) { oldId, newId in
            guard model[keyPath: urlKeyPath] != nil else { return }
            itemIdHasUrl = model.id
        }
        .onChange(of: model[keyPath: urlKeyPath]) { oldValue, newValue in
            guard oldValue == nil else { return }
            guard itemIdHasUrl != model.id else { return }
            withAnimation { isEditing = true }
        }
#if !os(tvOS)
        .onDrop(of: [.fileURL], delegate: FileDropDelegate(for: fileTypes, updateFile: updateFile))
#endif
        .sheet(isPresented: $isEditing) {
            DetailItemEditorView(model: model, editController: editController, nameKeyPath: nameKeyPath, categoryKeyPath: categoryKeyPath, tagsKeyPath: tagsKeyPath, descriptionKeyPath: descriptionKeyPath)
            
                .presentationContentInteraction(.resizes)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if model[keyPath: urlKeyPath] != nil {
                    Button {
                        withAnimation { isEditing = true }
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
        }
        .toolbarRole(.editor)
    }
}

private extension FileDetailEditorView {
    @ViewBuilder
    var initialFileImporterView: some View {
        ZStack {
            Color.clear
            
            importer
        }
        .opacity(model[keyPath: urlKeyPath] == nil ? 1 : 0)
        .transition(.scale)
    }
}

private extension FileDetailEditorView where Inside == EmptyView {
    @ViewBuilder
    var contentView: some View {
        VStack(spacing: 0) {
            DetailOverlayView(itemId: model.id, model: model, nameKeyPath: nameKeyPath, categoryKeyPath: categoryKeyPath, tagsKeyPath: tagsKeyPath, descriptionKeyPath: descriptionKeyPath)
            
            editor            
        }
        .padding()
        .opacity(model[keyPath: urlKeyPath] != nil ? 1 : 0)
        .transition(.scale)
    }

    private func updateFile(url: URL) {
        editController.resetFile(url: url, in: model)
    }
}

private extension FileDetailEditorView {
    @ViewBuilder
    var contentView: some View {
        VStack(spacing: 8) {
            inside
                .overlay(alignment: .bottom) {
                    DetailOverlayView(itemId: model.id, model: model, nameKeyPath: nameKeyPath, categoryKeyPath: categoryKeyPath, tagsKeyPath: tagsKeyPath, descriptionKeyPath: descriptionKeyPath)
                        .padding()
                }
                .opacity(model[keyPath: urlKeyPath] != nil ? 1 : 0)
                .transition(.scale)
            
            editor
        }
    }

    private func updateFile(url: URL) {
        editController.resetFile(url: url, in: model)
    }
}
