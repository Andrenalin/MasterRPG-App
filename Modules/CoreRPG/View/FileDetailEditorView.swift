// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

public struct FileDetailEditorView<EditController: EditControllable, Importer: View, Inside: View, Editor: View, Bottom: View>: View where EditController.Model.ID == UUID {
    public init(model: EditController.Model, editController: EditController, fileTypes: [UTType], @ViewBuilder importer: () -> Importer, @ViewBuilder background: () -> Inside, @ViewBuilder editor: () -> Editor = EmptyView.init, @ViewBuilder bottom: () -> Bottom = EmptyView.init) {
        self.model = model
        self.editController = editController
        self.fileTypes = fileTypes
        self.importer = importer()
        self.background = background()
        self.editor = editor()
        self.bottom = bottom()
        self.cacheItemListModel = CacheItemListModel()
    }

    let model: EditController.Model
    let editController: EditController
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
    @State private var itemIdHasUrl: EditController.Model.ID = UUID()

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
            guard model.url != nil else { return }
            itemIdHasUrl = model.id
        }
        .onChange(of: model.name, initial: true) {
            guard model.name.isEmpty && (model.url != nil || model.specialCategory) else { return }
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
        .applyIf(model.category != .folder) {
            $0.onDrop(of: [.fileURL], delegate: FileDropDelegate(for: fileTypes, updateFile: updateFile))
        }
#endif
        .sheet(isPresented: $isEditing) {
            DetailItemEditorView(model: model, editController: editController, name: \.name, category: \.category, tags: \.tags, description: \.information)
            
                .presentationContentInteraction(.resizes)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if model.url != nil || model.specialCategory {
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
        if model.specialCategory == false && model.url != nil {
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
        .opacity(model.url == nil && model.specialCategory == false ? 1 : 0)
        .transition(.scale)
    }

    @ViewBuilder
    var bottomView: some View {
        if model.url != nil && model.specialCategory == false {
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
        }
        .padding()
        .opacity(model.url != nil || model.specialCategory ? 1 : 0)
        .transition(.scale)
    }

    private func updateFile(url: URL) {
        editController.resetFile(url: url, in: model)
    }
}
