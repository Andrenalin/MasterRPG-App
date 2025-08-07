// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

public struct FileDetailEditorView<Model: Identifiable, EditController: EditControllable, Importer: View, Inside: View, Editor: View, Bottom: View>: View where Model.ID == UUID, Model == EditController.Model {
    public init(model: Model, editController: EditController, name: KeyPath<Model, String>, category: KeyPath<Model, ItemListCategory>, tags: KeyPath<Model, [String]>, description: KeyPath<Model, String>, url: KeyPath<Model, URL?>, specialCategory: KeyPath<Model, Bool>, fileTypes: [UTType], @ViewBuilder importer: () -> Importer, @ViewBuilder background: () -> Inside, @ViewBuilder editor: () -> Editor = EmptyView.init, @ViewBuilder bottom: () -> Bottom = EmptyView.init) {
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
        self.background = background()
        self.editor = editor()
        self.bottom = bottom()
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
    let background: Inside
    let editor: Editor
    let bottom: Bottom
    let cacheItemListModel: CacheItemListModel

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    @State private var isEditing = false
    @State private var itemIdHasUrl: Model.ID = UUID()

    @Environment(GroupItemSelectionModel.self) private var selection

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
    var backgroundView: some View {
        if model[keyPath: specialCategory] == false && model[keyPath: url] != nil {
            background
        }
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
        .opacity(model[keyPath: url] == nil && model[keyPath: specialCategory] == false ? 1 : 0)
        .transition(.scale)
    }

    @ViewBuilder
    var bottomView: some View {
        if model[keyPath: url] != nil && model[keyPath: specialCategory] == false {
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
            DetailOverlayView(itemId: model.id, model: model, nameKeyPath: name, categoryKeyPath: category, tagsKeyPath: tags, descriptionKeyPath: description)

            editor
        }
        .padding()
        .opacity(model[keyPath: url] != nil || model[keyPath: specialCategory] ? 1 : 0)
        .transition(.scale)
    }

    private func updateFile(url: URL) {
        editController.resetFile(url: url, in: model)
    }
}
