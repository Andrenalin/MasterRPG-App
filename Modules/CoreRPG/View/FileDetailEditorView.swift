// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

public struct FileDetailEditorView<Model: Identifiable, EditController: EditControllable, Importer: View, Inside: View, Editor: View>: View where Model.ID == UUID, Model == EditController.Model {
    public init(model: Model, editController: EditController, name: KeyPath<Model, String>, category: KeyPath<Model, ItemListCategory>, tags: KeyPath<Model, [String]>, description: KeyPath<Model, String>, url: KeyPath<Model, URL?>, specialCategory: KeyPath<Model, Bool>, fileTypes: [UTType], @ViewBuilder importer: () -> Importer, @ViewBuilder inside: () -> Inside, @ViewBuilder editor: () -> Editor = EmptyView.init) {
        self.model = model
        self.editController = editController
        self.name = name
        self.category = category
        self.tags = tags
        self.description = description
        self.url = url
        self.specialCategory = specialCategory
        self.fileTypes = fileTypes
        self.importer = importer()
        self.inside = inside()
        self.hasInside = true
        self.editor = editor()
        self.cacheItemListModel = CacheItemListModel()
    }

    public init(model: Model, editController: EditController, name: KeyPath<Model, String>, category: KeyPath<Model, ItemListCategory>, tags: KeyPath<Model, [String]>, description: KeyPath<Model, String>, url: KeyPath<Model, URL?>, specialCategory: KeyPath<Model, Bool>, fileTypes: [UTType], @ViewBuilder importer: () -> Importer, @ViewBuilder editor: () -> Editor = EmptyView.init) where Inside == EmptyView {
        self.model = model
        self.editController = editController
        self.name = name
        self.category = category
        self.tags = tags
        self.description = description
        self.url = url
        self.specialCategory = specialCategory
        self.fileTypes = fileTypes
        self.importer = importer()
        self.inside = EmptyView()
        self.hasInside = false
        self.editor = editor()
        self.cacheItemListModel = CacheItemListModel()
    }

    let model: Model
    let editController: EditController
    let name: KeyPath<Model, String>
    let category: KeyPath<Model, ItemListCategory>
    let tags: KeyPath<Model, [String]>
    let description: KeyPath<Model, String>
    let url: KeyPath<Model, URL?>
    let specialCategory: KeyPath<Model, Bool>
    let fileTypes: [UTType]
    let importer: Importer
    let inside: Inside
    let hasInside: Bool
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
        .animation(.default, value: model[keyPath: url])
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model[keyPath: name], initial: true) {
            guard model[keyPath: name].isEmpty && (model[keyPath: url] != nil || model[keyPath: specialCategory]) else { return }
            withAnimation { isEditing = true }
        }
        .onChange(of: model.id) { oldId, newId in
            guard model[keyPath: url] != nil else { return }
            itemIdHasUrl = model.id
        }
        .onChange(of: model[keyPath: url]) { oldValue, newValue in
            guard oldValue == nil else { return }
            guard itemIdHasUrl != model.id else { return }
            withAnimation { isEditing = true }
        }
#if !os(tvOS)
        .applyIf(model[keyPath: category] != .folder) {
            $0.onDrop(of: [.fileURL], delegate: FileDropDelegate(for: fileTypes, updateFile: updateFile))
        }
#endif
        .sheet(isPresented: $isEditing) {
            DetailItemEditorView(model: model, editController: editController, name: name, category: category, tags: tags, description: description)
            
                .presentationContentInteraction(.resizes)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if model[keyPath: url] != nil || model[keyPath: specialCategory] {
                    Button {
                        withAnimation { isEditing = true }
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
        }
    }
}

private extension FileDetailEditorView {
    @ViewBuilder
    var initialFileImporterView: some View {
        ZStack {
            Color.clear
            
            importer
                .padding(32)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
        }
        .opacity(model[keyPath: url] == nil && !model[keyPath: specialCategory] ? 1 : 0)
        .transition(.scale)
    }
    
    @ViewBuilder
    var contentView: some View {
        if hasInside {
            contentInsideView
        } else {
            contentWithoutInsideView
        }
    }
}

private extension FileDetailEditorView {
    @ViewBuilder
    var contentWithoutInsideView: some View {
        VStack(spacing: 0) {
            DetailOverlayView(itemId: model.id, model: model, nameKeyPath: name, categoryKeyPath: category, tagsKeyPath: tags, descriptionKeyPath: description)
            
            editor            
        }
        .padding()
        .opacity(model[keyPath: url] != nil || model[keyPath: specialCategory] ? 1 : 0)
        .transition(.scale)
    }

    @ViewBuilder
    var contentInsideView: some View {
        VStack(spacing: 8) {
            inside
                .overlay(alignment: .bottom) {
                    DetailOverlayView(itemId: model.id, model: model, nameKeyPath: name, categoryKeyPath: category, tagsKeyPath: tags, descriptionKeyPath: description)
                        .padding()
                }
                .opacity(model[keyPath: url] != nil || model[keyPath: specialCategory] ? 1 : 0)
                .transition(.scale)
            
            editor
        }
    }

    private func updateFile(url: URL) {
        editController.resetFile(url: url, in: model)
    }
}
